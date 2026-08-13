#include "predictions.h"
#include "include/ISS.h"

#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>

#define PREDICTION_TTL_MS 600

static long long now_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (long long)tv.tv_sec * 1000 + tv.tv_usec / 1000;
}

static long long lastCommandMs = 0;
static unsigned int lastSpaceCount = 0;

void predictions_force_reset(void) {
    iss_reset_predictions();
    lastSpaceCount = 0;
    lastCommandMs = 0;
}

void predictions_refresh_if_stale(void) {
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
            fprintf(stderr, "instantswitch: predictions reset (%s)\n",
                    layoutChanged ? "space list changed" : "idle");
        }
    }
    lastCommandMs = t;
}
