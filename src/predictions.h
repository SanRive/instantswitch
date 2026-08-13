#pragma once
#include <stdbool.h>

/*
 * ISS caches a per-display "predicted" space index after every switch and uses
 * it instead of the real one, so a rapid burst of presses does not race the
 * WindowServer. It never invalidates that cache. Any space change ISS did not
 * perform -- macOS auto-switching you into a newly created fullscreen space,
 * clicking a desktop in Mission Control, pressing ctrl+arrow -- leaves it stale,
 * and iss_should_block_switch() then refuses moves because it believes you are
 * still parked on an edge.
 *
 * Call this immediately before every switch. It drops the cache unless the
 * press is part of a burst and the space list is unchanged.
 */
void predictions_refresh_if_stale(void);

/* Force the next switch to use the real index (also resets burst tracking). */
void predictions_force_reset(void);
