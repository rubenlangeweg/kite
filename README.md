# Kite

Native macOS SwiftUI git client to replace GitKraken for daily basic-flow work
(fetch, pull, push, create branch, checkout) across repos under `~/Developer`.

Target: macOS 15+, Xcode 16+, Swift 5.9+.

## Prereqs

```bash
brew install xcodegen swiftformat swiftlint
```

You also need Xcode 16+ installed at `/Applications/Xcode.app` and Apple's
Command Line Tools (for `git`).

## Quickstart

```bash
xcodegen generate
open Kite.xcodeproj
# ⌘R to run, ⌘U to run tests
```

The `Kite.xcodeproj` bundle is generated from `project.yml` — do not edit it by
hand. Any build-setting change goes through `project.yml` followed by
`xcodegen generate`.

## Install (Release build)

Build a signed-to-run-locally Release bundle:

```
scripts/build_release.sh
```

Drag `build/Build/Products/Release/Kite.app` into `/Applications`. The
first launch from Finder triggers macOS's "unsigned app from an
unidentified developer" dialog; right-click → Open → Open anyway.
Subsequent launches don't prompt.

To install on a different Mac, re-run `scripts/build_release.sh` on that
machine — the ad-hoc signature is machine-local.

Sanity-check the built bundle against the cancellation invariant:

```
scripts/smoke_launch.sh
```

It launches Kite, quits it, and verifies no leaked `git` subprocesses.

No DMG, no notarization in v1.

## Command-line build & test

`xcode-select` on this machine may point at the Command Line Tools rather than
Xcode.app. Every `xcodebuild` invocation must set `DEVELOPER_DIR` explicitly:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -scheme Kite -configuration Debug build
xcodebuild test -scheme Kite -destination 'platform=macOS' -configuration Debug
swiftformat Sources Tests --lint   # swiftformat 0.61+ requires paths BEFORE --lint
swiftlint --strict
```

Do NOT run `sudo xcode-select -s …`; use the env var per-invocation.

## Mission context

This project is executed by Claude Code agents following the mission package
under [`.factory/missions/kite-v1/`](.factory/missions/kite-v1/mission.md).
Workers must read `AGENTS.md` and `INTERFACES.md` in that directory before
touching any file.
