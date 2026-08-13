// Resident ISS daemon: holds the event tap alive (like the GUI app does) and
// switches on commands read from stdin ("left\n" / "right\n").
#include "include/ISS.h"
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>
#include <string.h>
#include <unistd.h>

// ISS caches a per-display "predicted" space index after every switch and uses
// it instead of the real one, so that a rapid burst of presses does not race
// the WindowServer. It never invalidates that cache. Any space change ISS did
// not perform -- macOS auto-switching you into a newly created fullscreen
// space, clicking a desktop in Mission Control, pressing ctrl+arrow -- leaves
// the cache stale, and iss_should_block_switch() then refuses moves forever
// because it thinks you are still parked on an edge.
//
// The cache is only useful within a burst. Drop it when the press is not part
// of one, or when the space list changed underneath us.
#define PREDICTION_TTL_MS 600

static long long now_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (long long)tv.tv_sec * 1000 + tv.tv_usec / 1000;
}

static long long lastCommandMs = 0;
static unsigned int lastSpaceCount = 0;

static void refresh_predictions_if_stale(void) {
    const long long t = now_ms();
    const bool idle = (t - lastCommandMs) > PREDICTION_TTL_MS;

    ISSSpaceInfo info;
    bool layoutChanged = false;
    if (iss_get_space_info(&info)) {
        layoutChanged = (lastSpaceCount != 0 && info.spaceCount != lastSpaceCount);
        lastSpaceCount = info.spaceCount;
    }

    if (idle || layoutChanged) {
        iss_reset_predictions();
        if (getenv("ISSD_DEBUG")) {
            fprintf(stderr, "issd: predictions reset (%s)\n",
                    layoutChanged ? "space list changed" : "idle");
        }
    }
    lastCommandMs = t;
}

static void onStdin(CFFileDescriptorRef f, CFOptionFlags cbTypes, void *info) {
    char buf[64];
    ssize_t n = read(0, buf, sizeof(buf) - 1);
    if (n <= 0) { CFRunLoopStop(CFRunLoopGetCurrent()); return; }
    buf[n] = 0;
    for (char *p = buf; *p; p++) if (*p == '\n' || *p == '\r') *p = 0;
    if (strcmp(buf, "left") == 0)  { refresh_predictions_if_stale(); printf("%d\n", iss_switch(ISSDirectionLeft)); }
    else if (strcmp(buf, "right") == 0) { refresh_predictions_if_stale(); printf("%d\n", iss_switch(ISSDirectionRight)); }
    else if (strcmp(buf, "reset") == 0) { iss_reset_predictions(); lastSpaceCount = 0; printf("reset\n"); }
    else if (strncmp(buf, "speed ", 6) == 0) { iss_set_gesture_speed(atof(buf + 6)); printf("speed=%s\n", buf + 6); }
    else if (strcmp(buf, "quit") == 0) { CFRunLoopStop(CFRunLoopGetCurrent()); return; }
    fflush(stdout);
    CFFileDescriptorEnableCallBacks(f, kCFFileDescriptorReadCallBack);
}

int main(void) {
    if (!iss_init()) { fprintf(stderr, "iss_init failed\n"); return 1; }
    CFFileDescriptorRef fd = CFFileDescriptorCreate(NULL, 0, false, onStdin, NULL);
    CFRunLoopSourceRef src = CFFileDescriptorCreateRunLoopSource(NULL, fd, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopDefaultMode);
    CFFileDescriptorEnableCallBacks(fd, kCFFileDescriptorReadCallBack);
    fprintf(stderr, "ready\n");
    CFRunLoopRun();
    iss_destroy();
    return 0;
}
