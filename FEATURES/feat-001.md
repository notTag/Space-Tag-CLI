# [001] Bounded flash on active space, persistent color on inactive space

- Status: open
- Created: 2026-05-30
- Priority: med
- Bump: minor

## What
Change agent-completion flash behavior based on whether the target space is active:
- Active space: flash the space label 5 times, then stop.
- Non-active space: skip the flashing entirely; instead leave the tab/pill in the changed (flash) color until that space becomes active.

## Why
Better notification system without being intrusive. A flash that repeats forever (or on a background space the user isn't looking at) is noisy. Bounding the flash to 5 cycles on the focused space, and holding a static color on background spaces, signals "agent done here" without distraction.

## Done When
- [ ] Flash activates exactly 5 times on the active space label, then stops.
- [ ] Non-active space label stays in the changed color (flash color, no flashing) until the space becomes active.
- [ ] When a non-active space becomes active, its held color clears (returns to normal / resolves per existing flash behavior).
