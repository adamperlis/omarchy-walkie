# Walkie for the Omarchy bar

Dictation and meeting status for [Walkie](https://trywalkie.com), as an
[Omarchy](https://omarchy.org) shell plugin: the Walkie mark sits in your bar,
shows a blinking dot while you dictate and a live waveform, timer, and
play/pause while a meeting records. Click the mark to open Walkie full screen.

## Requires the Walkie app

The widget is a status display and remote control for the Walkie desktop app —
install that first. On Arch/Omarchy, trust Walkie's package signing key
(fingerprint `7D83A6322DEC79B94A9BE087D51158E4F15B9894` — verify what you
import matches it):

```sh
curl -fsSL https://b150.s3.us-east-1.amazonaws.com/walkie/arch/x86_64/walkie-signing-key.asc -o /tmp/walkie-key.asc
sudo pacman-key --add /tmp/walkie-key.asc
sudo pacman-key --lsign-key 7D83A6322DEC79B94A9BE087D51158E4F15B9894
```

then add Walkie's package repository to `/etc/pacman.conf`. Every package and
the repository database are signed, so pacman verifies everything it installs
from here:

```ini
[walkie]
SigLevel = Required
Server = https://b150.s3.us-east-1.amazonaws.com/walkie/arch/$arch
```

then install with your package manager:

```sh
sudo pacman -Syu walkie-bin
```

(There is also a guided installer at
[trywalkie.com/docs/getting-started/walkie-on-linux](https://trywalkie.com/docs/getting-started/walkie-on-linux)
— read it before running anything, as with any installer.)

**The app ships this widget and offers to add it to your bar on first
launch** — most people never need this repo. It exists so the widget can also be browsed, read and installed the
Omarchy way:

```sh
omarchy plugin add https://github.com/adamperlis/omarchy-walkie.git --enable
```

Installing from git and from the app are exclusive: both register the id
`com.b150.walkie`, and Omarchy refuses a second claim. If you installed from
git, updates ride `omarchy plugin update`; the app leaves git checkouts alone.

Remove it any time with:

```sh
omarchy plugin remove com.b150.walkie
```

## What it does

The mark is always there — click it to open Walkie full screen. A status
strip appears beside it only while something is happening:

| State | Shows |
| --- | --- |
| Dictating | A blinking orange dot |
| Meeting recording | A live audio waveform, a running timer, and a play/pause button (click to pause/resume) |
| Idle | Nothing but the mark |

On a left or right (vertical) bar the strip stacks and folds to a compact
form. A dead or missing Walkie dims the mark.

## Settings

Configure from the bar's widget settings (or `~/.config/omarchy/shell.json`):

| Key | Default | What it does |
| --- | --- | --- |
| `command` | `walkie` | Executable for status and actions — absolute path for AppImage installs |
| `hideWhenIdle` | `false` | Only occupy bar space while recording or working |
| `fontFamily` | inherit | Override the bar font for status glyphs |
| `fontSize` | `14` | Icon size in pixels |

## A dictation hotkey to go with it

Wayland compositors hold global hotkeys, not apps. The Walkie app offers a
one-click setup; the equivalent block for `~/.config/hypr/bindings.lua`:

```lua
if o.cmd_present("walkie") then
  o.bind("SUPER + CTRL + M", "Toggle Walkie dictation", "walkie --toggle-transcription")
  o.bind("F10", "Walkie push-to-talk (start)", "walkie --start-transcription")
  o.bind("F10", "Walkie push-to-talk (stop)", "walkie --stop-transcription", { release = true })
end
o.window("^([Ww]alkie)$", { tag = "+floating-window", size = { "(monitor_w*0.65)", "(monitor_h*0.8)" } })
```

Then `hyprctl reload`. These keys are free on a stock Omarchy — Voxtype holds
Super+Ctrl+X and F9, and the Display panel holds Super+Ctrl+D.

## Development

This repo mirrors `packaging/omarchy-plugin/` in the Walkie app repository —
that copy is the source of truth, and releases sync here. Issues and ideas are
welcome; widget code fixes land upstream.

MIT licensed.
