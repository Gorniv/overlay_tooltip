## [Unreleased]

* Release tooltip models when their owning items unmount, change display index,
  or move to another controller; preserve replacement ownership by widget key.
* Clear retained models and callbacks when the controller is disposed, and avoid
  adding persistent subscriptions when reading its playback stream.
* Hide a removed active target safely without triggering tutorial completion.
* Release models held by pending automatic starts and snapshots from replaced
  controllers; unregister scaffold-owned readiness callbacks on unmount.
* Update active replacements and preserve navigation after target removal,
  without re-registering targets on every playback event.
* Deduplicate pending readiness checks and shared-future listeners; detach
  removed owners without retaining registration tokens until readiness resolves.
* Respect pause and completion when automatic-start results arrive, and notify
  completion only once per explicit start.

## [0.2.3] - 2023-06-16

* Fix Updates from 0.2.2 not reflecting

## [0.2.2] - 2023-04-29

* Ability to add preferred overlay widgets, this can help with gesture detection
* Updated android versions of example project

## [0.2.1] - 2022-07-21

* Null error fix

## [0.2.0] - 2022-07-15

* Ability to pause tooltip display without triggering `onDone` action
* Start tooltip display at specific displayIndex by passing value to start
  method `start(<optional displayIndex>)`
* Readme.md updates.

## [0.1.0] - 2022-02-07

* Improvements to access controller from OverlayTooltipScaffold in same context scope
* Tests coverage.
* Readme.md updates.

## [0.0.2] - 2021-11-06

* Readme.md and example project edits.

## [0.0.1] - 2021-11-06

* Initial development release.
