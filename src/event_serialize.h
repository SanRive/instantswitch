/*
 * C reimplementation of the CGEvent/IOHID serialization approach from
 * FasterSwiper. Copyright mgbowen. Apache License, Version 2.0.
 * https://github.com/mgbowen/FasterSwiper  (branch macos27)
 *
 * Reimplemented by geesawra (github.com/geesawra/InstantSpaceSwitcher,
 * commit 79a17c4) and vendored here. Retains FasterSwiper's data model and
 * type names. Distributed here under Apache-2.0; see LICENSE-APACHE and NOTICE.
 *
 * Unmodified by this project.
 */
#ifndef EVENT_SERIALIZE_H
#define EVENT_SERIALIZE_H

#include <ApplicationServices/ApplicationServices.h>
#include <stdbool.h>

/**
 * @brief Augments a synthetic dock-swipe CGEvent with the raw IOHID payload
 * that macOS 27 requires to recognize synthetic trackpad swipe gestures.
 *
 * The returned event is retained and the caller is responsible for releasing it.
 *
 * @param event A synthetic dock-swipe CGEvent with the public gesture fields set.
 * @return A retained, augmented CGEventRef, or NULL on failure.
 */
CGEventRef iss_augment_dock_swipe_event(CGEventRef event);

/**
 * @brief Returns true when the running OS is macOS 27 or later.
 *
 * On these versions, synthetic dock-swipe events must carry the raw IOHID
 * payload created by iss_augment_dock_swipe_event() in order to be honored.
 *
 * For testing, set the environment variable ISS_FORCE_EVENT_AUGMENTATION=1
 * to enable augmentation on any version, or =0 to disable it.
 */
bool iss_requires_event_augmentation(void);

#endif /* EVENT_SERIALIZE_H */
