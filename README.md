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
- **Text areas:** reads the line under the pointer, for example in Terminal and TextEdit.
- **VoiceOver-style wording:** name, then value, type and state, for example "Volume, 50%, slider". You choose the verbosity. Alternatively, it can use VoiceOver's own "Describe Item in Mouse Pointer" wording.
- **Unlabeled icons:** when an item has no label, VOHover reads the button or other item that contains it.
- **Toggle command:** turns hover speech on or off from any VoiceOver command (a key, a NumPad key or a trackpad gesture).
- **Settings window** laid out like System Settings, plus an optional menu bar item.

## Requirements

- macOS 14 or later
- Xcode Command Line Tools (`xcode-select --install`)
- VoiceOver

## Installation

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
   3. Pick `~/Library/Scripts/VOHover/Toggle VOHover.scpt`. VoiceOver says "Hover speech on" or "Hover speech off" each time you use it.
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
  log stream --level debug --predicate 'subsystem == "local.vohover"'
  ```

## Uninstall

First turn off Settings > General > Open at login. Then quit VOHover and run:

```sh
rm -rf ~/Applications/VOHover.app ~/Library/Scripts/VOHover
defaults delete local.vohover
tccutil reset All local.vohover
```
