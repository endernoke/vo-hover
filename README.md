# VOHover

VOHover makes VoiceOver speak the item under the mouse pointer without moving the VoiceOver cursor.

## Why

macOS has two built-in ways to hear what's under the pointer, and both have problems:

- **VoiceOver > Navigation > "VoiceOver cursor follows mouse"** speaks the item, but it also moves VoiceOver focus every time the mouse moves.
- **Read & Speak > "Speak item under the pointer"** leaves focus alone, but it uses a separate voice.
  - That voice often talks over VoiceOver.
  - Both voices pause and resume on the Control key, so pressing Control can stop one while starting the other.

VOHover speaks the item under the pointer through VoiceOver's own speech. There is one voice, Control silences it like any other VoiceOver speech, and focus stays where it is.

## Features

- **Hands-free hover reading:** speaks an item when the pointer rests on it, after a delay you can adjust. It reads the whole item, however long.
- **Only when zoomed:** optionally speaks only while Zoom magnifies the screen.
- **Text areas:** reads the line under the pointer, for example in Terminal and TextEdit.
- **VoiceOver-style wording:** name, then value, type and state, for example "Volume, 50%, slider". You choose the verbosity. Alternatively, it can use VoiceOver's own "Describe Item in Mouse Pointer" wording.
- **Unlabeled icons:** when an item has no label, VOHover reads the button or other item that contains it.
- **Toggle command:** turns hover speech on or off from any VoiceOver command (a key, a NumPad key or a trackpad gesture).
- **Settings window** laid out like System Settings, plus an optional menu bar item.

## Requirements

- macOS 14 or later
- VoiceOver

## Installation

### Homebrew

```sh
brew install --cask endernoke/tap/vohover
```

VOHover isn't signed with an Apple Developer ID, so the cask removes the download's quarantine flag to let it open. Each update may need the Accessibility permission allowed again.

### Download

1. From the [latest release](https://github.com/endernoke/vo-hover/releases/latest), download `VOHover-<version>.dmg`. It runs on both Apple silicon and Intel Macs.
2. Open the disk image and drag VOHover to Applications.
3. Open VOHover. Because it isn't notarized, macOS blocks it the first time: open System Settings > Privacy & Security and click Open Anyway.

### From source

Requires the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/endernoke/vo-hover.git
cd vo-hover
./install.sh          # build, install to ~/Applications, and open Settings
./install.sh --quiet  # same, but start in the background
```

`install.sh` signs the app with your Apple Development certificate if you have one, so its permissions survive rebuilds. If you don't, it signs the app ad hoc, and you'll need to allow the permissions again after each rebuild.

## Setup

1. **Let VoiceOver be scripted.** Open VoiceOver Utility, choose General, and turn on "Allow VoiceOver to be controlled with AppleScript".
2. **Allow the permissions.** macOS asks for these the first time VOHover needs them:
   - **Accessibility**, so VOHover can find the item under the pointer.
   - **Automation (VoiceOver)**, so VOHover can speak through VoiceOver.

   Settings > General shows the status of both.
3. **Optional: add a toggle command.**
   1. In VoiceOver Utility, choose Commands, set Command set to User, and click Edit.
   2. Click Add, choose an input, then choose Custom Commands > Run AppleScript Script.
   3. Pick `~/Library/Scripts/VOHover/Toggle VOHover.scpt`. VOHover creates this script the first time it opens. VoiceOver says "Hover speech on" or "Hover speech off" each time you use it.
4. **Optional:** turn on Settings > General > Open at login.

### Related built-in commands

VoiceOver can already move focus and the pointer on demand:

| Command | Action |
|---|---|
| VO-Shift-F5 | Move the VoiceOver cursor to the mouse pointer |
| VO-Command-F5 | Move the mouse pointer to the VoiceOver cursor |

## Troubleshooting

- **Nothing is spoken:** check that both permissions show "Allowed" in Settings > General, and that VoiceOver allows AppleScript control (Setup, step 1).
- **Debug log:**
  ```sh
  log stream --level debug --predicate 'subsystem == "io.github.endernoke.vohover"'
  ```

## Uninstall

First turn off Settings > General > Open at login. Then quit VOHover.

If you installed with Homebrew:

```sh
brew uninstall --zap --cask vohover
tccutil reset All io.github.endernoke.vohover
```

If you installed from source:

```sh
rm -rf ~/Applications/VOHover.app ~/Library/Scripts/VOHover
defaults delete io.github.endernoke.vohover
tccutil reset All io.github.endernoke.vohover
```

## Releasing

1. Set the new version in `Info.plist` (`CFBundleShortVersionString`, as `MAJOR.MINOR.PATCH` following [semantic versioning](https://semver.org)) and push the commit to `main`.
2. Publish a GitHub Release whose tag is `v` plus that version, for example `v0.0.2`, created from `main`. Either:
   - on GitHub, click **Draft a new release**, type the new tag, click **Generate release notes**, then **Publish release**; or
   - run `gh release create "v$(plutil -extract CFBundleShortVersionString raw Info.plist)" --generate-notes`.
3. The Build workflow builds a universal `VOHover-<version>.dmg` and attaches it to the release. For releases not marked as a pre-release, it also updates the cask in [endernoke/homebrew-tap](https://github.com/endernoke/homebrew-tap) if the `HOMEBREW_TAP_TOKEN` secret is set. If the tag doesn't match `Info.plist`, the workflow fails and attaches nothing.

`./build.sh --dmg` makes the same disk image locally. To keep users' permissions across updates without an Apple Developer ID, add a self-signed code-signing certificate as the `MACOS_CERT_P12` and `MACOS_CERT_PASSWORD` secrets (see the comments in `.github/workflows/build.yml`).
