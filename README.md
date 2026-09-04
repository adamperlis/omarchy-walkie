# Walkie for the Omarchy bar

Dictation and meeting status for [Walkie](https://trywalkie.com), as an
[Omarchy](https://omarchy.org) shell plugin: the Walkie mark sits in your bar,
shows whether Walkie is idle, recording, transcribing or in a meeting, and a
click starts dictation without touching the keyboard.

## Requires the Walkie app

The widget is a status display and remote control for the Walkie desktop app —
install that first:

```sh
curl -fsSL https://trywalkie.com/install.sh | sh
```

The installer adds Walkie's pacman repository, and **the app ships this widget
and offers to add it to your bar on first launch** — most people never need
this repo. It exists so the widget can also be browsed, read and installed the
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

| Action | Result |
| --- | --- |
| Left click | Toggle dictation (start, then stop and transcribe) |
| Right click | Open / focus the Walkie window |
| Middle click | Cancel the current recording |

While recording, the mark breathes slowly. Idle recedes; a dead or missing
Walkie shows a muted mic and any click launches the app.

## Settings

Configure from the bar's widget settings (or `~/.config/omarchy/shell.json`):

| Key | Default | What it does |
| --- | --- | --- |
| `command` | `walkie` | Executable for status and actions — absolute path for AppImage installs |
| `hideWhenIdle` | `false` | Only occupy bar space while recording or working |
| `showLabel` | `false` | Print the state name next to the icon |
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
