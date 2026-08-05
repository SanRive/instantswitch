// Resident ISS daemon: holds the event tap alive (like the GUI app does) and
// switches on commands read from stdin ("left\n" / "right\n").
#include "include/ISS.h"
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void onStdin(CFFileDescriptorRef f, CFOptionFlags cbTypes, void *info) {
    char buf[64];
    ssize_t n = read(0, buf, sizeof(buf) - 1);
    if (n <= 0) { CFRunLoopStop(CFRunLoopGetCurrent()); return; }
    buf[n] = 0;
    for (char *p = buf; *p; p++) if (*p == '\n' || *p == '\r') *p = 0;
    if (strcmp(buf, "left") == 0)  printf("%d\n", iss_switch(ISSDirectionLeft));
    else if (strcmp(buf, "right") == 0) printf("%d\n", iss_switch(ISSDirectionRight));
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
