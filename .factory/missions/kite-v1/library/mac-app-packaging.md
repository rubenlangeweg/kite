# Packaging a personal macOS SwiftUI app in 2026 (no Apple Developer account)

Scope: a single-user, personal-machine git client ("gitruben") that shells out to
`/usr/bin/git` and reads repo directories under `/Users/ruben/Developer`. Not for
distribution. Optimise for "works on my Mac, launches from the Dock, minimum
ceremony."

---

## 1. "Sign to Run Locally" in Xcode

In the target's *Signing & Capabilities* tab, set:

- **Team:** `None`
- **Signing Certificate:** `Sign to Run Locally` (this is the ad-hoc / `-` identity)

What this actually does:

- Xcode signs the `.app` bundle with an ad-hoc signature (no cert, no chain of
  trust). `codesign -dv` shows `Signature=adhoc`.
- macOS will launch the app without Gatekeeper prompts **only on the same Mac
  that signed it**. The local `syspolicyd` cache trusts the build because it
  came from a known local compile.

Limitations:

- **Runs only on the signing machine.** Copy the `.app` to another Mac and
  Gatekeeper will refuse to launch it. The workaround on the other Mac is
  right-click -> *Open* once, or `xattr -dr com.apple.quarantine /path/to.app`.
- **No entitlements that require a team** (iCloud, Push, Associated Domains,
  DeviceCheck, etc.). None of those are needed for a git client.
- **No automatic updates** via Sparkle EdDSA-only mode unless you wire it up
  manually.
- **Reinstall / rebuild invalidates TCC grants.** If you grant Full Disk Access
  or Automation to the app, the grant is keyed to the code signature. Each
  ad-hoc rebuild can produce a different CDHash, which sometimes forces macOS
  to re-prompt. Mitigation: use a stable self-signed cert (see section 7) if
  this gets annoying.

Rule of thumb: "Sign to Run Locally" is the right default for this project.
Don't overthink it.

---

## 2. App sandbox considerations

A git client that reads arbitrary working copies and execs `/usr/bin/git` is
fundamentally at odds with the App Sandbox. You have two honest choices.

### Option A: Disable the sandbox (recommended for gitruben)

In `gitruben.entitlements`:

```xml
<key>com.apple.security.app-sandbox</key>
<false/>
```

Or just uncheck *App Sandbox* in *Signing & Capabilities*. Trade-offs:

- **Pros**
  - `Process` can exec `/usr/bin/git` with no extra wiring.
  - `FileManager` can read anywhere the running user can read (`~/Developer`,
    `~/Documents`, external drives, `/tmp`, wherever).
  - No security-scoped bookmarks, no `NSOpenPanel` dance just to remember a
    repo path across launches.
  - You can write a plain `~/Library/Application Support/gitruben/state.json`
    without container redirection.
- **Cons**
  - Cannot ship via Mac App Store (irrelevant here).
  - Full Disk Access / Files & Folders TCC prompts still apply the first time
    the app touches protected locations (Desktop, Documents, Downloads,
    iCloud Drive, removable volumes). `~/Developer` is not protected, so you
    won't see prompts for normal use.
  - Slightly larger blast radius if the app is ever compromised, but the user
    is the only attacker surface here.

### Option B: Keep the sandbox on (the "correct" way)

Entitlements you'd need:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.files.bookmarks.app-scope</key>
<true/>
<key>com.apple.security.temporary-exception.files.absolute-path.read-write</key>
<array>
  <string>/Users/ruben/Developer/</string>
</array>
```

Plus code changes:

1. User picks each repo via `NSOpenPanel` (sandbox only grants access to
   user-selected URLs).
2. Persist a **security-scoped bookmark** per repo
   (`URL.bookmarkData(options: .withSecurityScope, ...)`).
3. On relaunch, resolve the bookmark and wrap reads in
   `url.startAccessingSecurityScopedResource()` /
   `stopAccessingSecurityScopedResource()`.
4. `/usr/bin/git` is outside the container — you'd need
   `com.apple.security.inherit` on a helper, or more realistically call
   libgit2 in-process to avoid Process altogether. Shelling out to `git` from
   inside a strict sandbox is fighting the system.

Verdict: **use Option A.** Sandbox hardening makes sense when you don't trust
the user base. For a solo tool on one Mac, it's pure friction.

---

## 3. Hardened runtime

Hardened runtime is only required for notarization. For a personal, locally-
signed app:

- **Skip it.** Leave *Hardened Runtime* unchecked in *Signing & Capabilities*.
- If you ever turn it on, you'll need explicit entitlements like
  `com.apple.security.cs.allow-unsigned-executable-memory` or
  `com.apple.security.cs.disable-library-validation`, plus
  `com.apple.security.inherit` propagation rules for the `git` subprocess.
  None of that is worth it until you notarize.

Turn it on later only if you decide to notarize for sharing (section 7).

---

## 4. Running `Process` on `/usr/bin/git`

With sandbox **off** and hardened runtime **off**, there are no extra
entitlements. Just:

```swift
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
p.arguments = ["-C", repoPath, "status", "--porcelain=v2"]
p.standardOutput = Pipe()
p.standardError = Pipe()
try p.run()
p.waitUntilExit()
```

Notes specific to 2026 macOS:

- `/usr/bin/git` is still the Command Line Tools shim that execs the selected
  Xcode toolchain's git. It works without `xcode-select` being pointed
  anywhere in particular, but if Xcode was removed entirely you'll get the
  infamous "xcrun: error: invalid active developer path" message on stderr.
  Detect that and surface a clear "install Command Line Tools" error.
- Pass a clean environment. In particular unset `GIT_DIR`, `GIT_WORK_TREE`,
  `GIT_INDEX_FILE`, and consider `GIT_TERMINAL_PROMPT=0` so credential
  prompts don't hang your UI. Also set `GIT_OPTIONAL_LOCKS=0` for read-only
  queries that don't need to take the index lock.
- If you ever enable hardened runtime, you'll also need
  `com.apple.security.cs.allow-jit` off (fine) but you *will* need
  `com.apple.security.inherit` so the child inherits sandbox/entitlement
  state cleanly. Again — skip hardened runtime for now.

---

## 5. App icon

Xcode 16+ uses a single PNG in the asset catalog (single-size icon slot) and
generates the rest at build time. The older multi-size `AppIcon.appiconset`
still works.

Quickest path:

1. Design a 1024x1024 PNG (sRGB, no alpha matters less than it used to but
   keep it opaque for the Dock).
2. Drop it into `Assets.xcassets -> AppIcon -> Any Appearance (Single Size)`.
3. Xcode handles `icon_16x16@2x`, `icon_32x32`, ... down through the set.

If you want an actual `.icns` (for a DMG background, CLI tooling, etc.):

```bash
ICON=icon.png
mkdir icon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICON" --out "icon.iconset/icon_${s}x${s}.png"
  d=$((s*2))
  sips -z $d $d "$ICON" --out "icon.iconset/icon_${s}x${s}@2x.png"
done
iconutil -c icns icon.iconset -o AppIcon.icns
rm -rf icon.iconset
```

For a scrappy icon, a solid-background SF Symbol rendered at 1024 via
`Image(systemName: "arrow.triangle.branch").renderingMode(...)` exported from
Preview/Figma is fine. Don't waste a day on this.

---

## 6. Launch from Dock / Finder

Things that must be correct in `Info.plist` for a clean Dock launch:

- `CFBundleIdentifier` — reverse-DNS, unique on your machine. E.g.
  `nl.rb2.ruben.gitruben`. TCC, `UserDefaults`, and Launch Services all key
  off this.
- `CFBundleName` / `CFBundleDisplayName` — "gitruben". Display name is what
  shows under the Dock icon.
- `CFBundleShortVersionString` and `CFBundleVersion` — even `"0.1"` / `"1"`
  are fine, but don't leave them as `$(MARKETING_VERSION)` literal strings.
- `LSMinimumSystemVersion` — whatever your deployment target is (probably
  macOS 14+ for SwiftUI-modern APIs).
- `LSApplicationCategoryType` — `public.app-category.developer-tools`. Purely
  cosmetic (affects category in Launchpad / App Store metadata) but it's a
  one-liner and looks right.
- `NSHighResolutionCapable` — `true`. Default in modern templates, just
  verify.
- `NSHumanReadableCopyright` — optional, but "Copyright (c) 2026 Ruben" looks
  less amateur in About.

Install path: drop the built `.app` into `/Applications` (or `~/Applications`
to keep it user-scoped — both are indexed by Spotlight and Launch Services).
After the first launch Launch Services caches the bundle; re-register with
`lsregister -f /Applications/gitruben.app` if the icon ever goes stale.

---

## 7. Distribution later (optional)

If a colleague asks "can I try it?", two tiers:

### Tier 1: self-signed, no notarization

- Create a self-signed *Developer ID-style* cert via Keychain Access ->
  *Certificate Assistant* -> *Create a Certificate...* -> Code Signing.
- Sign: `codesign --force --deep --sign "Ruben SelfSign" gitruben.app`.
- Ship over AirDrop / a zip. Recipient right-clicks -> *Open* the first time.
  Gatekeeper will warn ("unidentified developer") but allow.

This is basically the same as ad-hoc from the recipient's POV, just with a
stable CDHash across rebuilds.

### Tier 2: Developer ID + notarization (if you get a paid account)

Minimum ceremony:

```bash
# One-time
xcrun notarytool store-credentials gitruben-notary \
  --apple-id ruben@rb2.nl --team-id TEAMID

# Each build
codesign --force --deep --options=runtime \
  --sign "Developer ID Application: Ruben (TEAMID)" \
  --entitlements gitruben.entitlements gitruben.app

ditto -c -k --keepParent gitruben.app gitruben.zip
xcrun notarytool submit gitruben.zip --keychain-profile gitruben-notary --wait
xcrun stapler staple gitruben.app
```

Requires hardened runtime (`--options=runtime`) and a real
`gitruben.entitlements` — this is where sandbox-off still works but you need
to explicitly declare it.

### Packaging the `.app`

For a shareable drag-to-Applications install, `create-dmg` is the least
painful:

```bash
brew install create-dmg
create-dmg \
  --volname "gitruben" \
  --window-size 540 380 \
  --icon-size 96 \
  --app-drop-link 380 180 \
  --icon "gitruben.app" 160 180 \
  gitruben.dmg gitruben.app
```

Alternative for totally casual sharing: just zip the `.app` and send it. DMGs
preserve extended attributes (icons, quarantine state) slightly better, but
for a personal tool, zip is fine.

---

## 8. File access outside `~/Developer`

With sandbox off, nothing breaks at the entitlement layer. The wrinkles are
all TCC:

- **`~/Desktop`, `~/Documents`, `~/Downloads`, iCloud Drive, network shares,
  removable volumes** — each triggers a one-time TCC prompt the first time
  gitruben reads them. User clicks *Allow*, grant is remembered per bundle ID
  + code signature. Unsigned ad-hoc builds may re-prompt after rebuilds.
- **`/tmp` and `/var/folders/...`** — fine, no TCC gate.
- **Other users' home directories** — blocked by POSIX perms, not TCC.
- **Full Disk Access** — you only need to grant this in
  *System Settings -> Privacy & Security -> Full Disk Access* if you want to
  skip the per-folder prompts entirely, or if you plan to read things like
  `~/Library/Mail` (unlikely for a git client). Usually not needed.
- **Network-mounted repos (SMB/NFS/Cloud)** — work fine but expect slow
  `git status` and watch out for case-insensitivity surprises; unrelated to
  packaging.
- **Symlinks pointing outside `~/Developer`** — followed normally. If the
  symlink target is in a TCC-gated location (e.g. a Desktop checkout), the
  prompt fires on first access.

Practical recommendation: keep all repos under `~/Developer` so the user never
sees a TCC prompt. If you grow past that, just click through the prompts once
per location — they persist.

---

## TL;DR recipe for gitruben

1. Xcode target -> Signing: *Sign to Run Locally*, team *None*.
2. Capabilities: **App Sandbox off, Hardened Runtime off.**
3. `Info.plist`: set `CFBundleIdentifier` (`nl.rb2.ruben.gitruben`),
   `LSApplicationCategoryType` (`public.app-category.developer-tools`),
   versions.
4. Drop a 1024x1024 PNG into `Assets.xcassets/AppIcon`.
5. Archive -> Export -> "Copy App" -> drag to `/Applications`.
6. Worry about notarization, DMGs, and sandbox hardening the day someone
   asks for a copy. Not before.
