// Walkie — Omarchy bar widget.
//
// A persistent Walkie mark (click → open Walkie full screen) plus a notch-style
// status strip that appears only while something is happening:
//   • dictating      → a blinking orange dot
//   • meeting record  → a live audio waveform + timer + play/pause
//   • idle / offline  → just the mark (or nothing, with hideWhenIdle)
//
// Depends on QtQuick + Quickshell.Io ONLY — never qs.Ui / qs.Commons, which
// are versioned with Omarchy and would break the widget on a shell upgrade.
// Phase/offline come from `walkie status --watch`; the richer meeting fields
// and the waveform come from Walkie's runtime files, read directly.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
  id: root

  // `var`, NOT QtObject. Omarchy fills this after loading, and with the
  // stricter type the assignment did not take: `bar` stayed null, so every
  // bar-derived value silently used its fallback — the mark rendered the
  // literal "white" below while the bar's icons were black (Adam,
  // 2026-09-08). `settings` was declared `var` and always worked, which is
  // what gave the type away. The upstream docs use `bar` untyped.
  property var bar: null
  property string moduleName: ""
  property var settings: ({})

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return (value === undefined || value === null) ? fallback : value
  }
  readonly property string walkieCmd: String(setting("command", "walkie"))
  readonly property bool hideWhenIdle: setting("hideWhenIdle", false) === true
  readonly property string fontFamily: {
    var chosen = String(setting("fontFamily", ""))
    if (chosen) return chosen
    return root.bar && root.bar.fontFamily ? root.bar.fontFamily : "monospace"
  }
  // The bar exposes barSize, NOT a font size — an earlier attempt to inherit
  // `bar.fontSize` was reading a property that does not exist. Scale the mark
  // from the bar's own thickness so it sits at the same weight as the glyphs
  // beside it on any bar, and let the user override outright.
  // TEXT size — the meeting timer and the next-meeting label. Not the mark:
  // see markSize below for why the two must not share a number.
  readonly property int fontSize: {
    var chosen = Number(setting("fontSize", 0))
    if (chosen >= 8 && chosen <= 48) return chosen
    return Math.max(8, Math.round(root.barSize * 0.54))
  }

  // The MARK's box, deliberately independent of fontSize.
  //
  // A text glyph's ink fills roughly two thirds of its em box, but the
  // dot-globe fills its box edge to edge — the outer ring sits at 6.1/16 of
  // the width, so the drawn mark is ~86% of whatever box it is given. Feed
  // both the same number and the mark reads far bigger than the glyphs
  // beside it, which is exactly how it looked (Adam, 2026-09-09).
  //
  // Tunable live, because getting this exactly right is an eyeball job and a
  // release round trip is a poor way to do it:
  //   omarchy bar set com.b150.walkie markScale 0.45
  readonly property real markScale: {
    var v = Number(setting("markScale", 0))
    return (v >= 0.2 && v <= 1.0) ? v : 0.5
  }
  readonly property int markSize: Math.max(8, Math.round(root.barSize * root.markScale))
  // Mirror the bar's icon colour. `bar.foreground` is the live value the shell
  // pushes on every theme change and is authoritative. The palette file is the
  // backstop for any moment `bar` is not populated — it is the SAME file
  // Walkie's own UI themes from (omarchy.rs::palette_path), so the two can
  // never disagree, and it beats a hardcoded colour that can land white on a
  // white bar.
  readonly property color fg: {
    if (root.bar && root.bar.foreground) return root.bar.foreground
    if (root.paletteFg.a > 0) return root.paletteFg
    return "white"
  }
  property color paletteFg: "transparent"
  readonly property color accent: "#fb4501"
  // Omarchy exposes bar.vertical directly; bar.position is the older spelling
  // and stays as the fallback. On a left/right bar widgets take a compact
  // icon-only form (shell/plugins/bar/README.md).
  readonly property bool vertical: {
    if (root.bar && root.bar.vertical !== undefined) return root.bar.vertical === true
    var p = root.bar ? String(root.bar.position) : ""
    return p === "left" || p === "right"
  }

  // The bar's own thickness — 26px horizontal, 28px vertical upstream. The
  // widget's implicit size across the bar must MATCH this or the container
  // parks it against the leading edge instead of the centre line, which is
  // what left the mark sitting high above its neighbours (Adam, 2026-09-08).
  readonly property int barSize: {
    var s = root.bar ? Number(root.bar.barSize) : 0
    return (s >= 12 && s <= 96) ? s : (root.vertical ? 28 : 26)
  }

  // ── phase / offline (Waybar-shaped stream) ─────────────────────────────
  property string phase: "stopped"
  readonly property bool busy: phase === "analyzing" || phase === "transcribing"
                               || phase === "thinking" || phase === "speaking"
  readonly property bool dictating: phase === "recording"
  readonly property bool offline: phase === "stopped"

  // ── richer state from runtime-state.json ───────────────────────────────
  property bool meetingActive: false
  property bool meetingPaused: false
  // The next-meeting label the macOS menu bar shows, rendered and translated
  // app-side (next_meeting::render_title) so this widget cannot drift from it.
  property string nextMeeting: ""
  property string nextMeetingLink: ""
  // Never while a meeting is RECORDING: the strip beside the mark is already
  // showing that meeting's clock, and a countdown to the next one next to it
  // reads as two clocks disagreeing.
  readonly property bool showNext: nextMeeting.length > 0 && !meetingActive
  property double meetingRecordedMs: 0
  property double stateUpdatedAt: 0
  property double nowMs: Date.now()

  readonly property double meetingElapsedMs: {
    if (!meetingActive) return 0
    var base = meetingRecordedMs
    if (!meetingPaused && stateUpdatedAt > 0)
      base += Math.max(0, nowMs - stateUpdatedAt)
    return base
  }
  function fmt(ms) {
    var s = Math.max(0, Math.floor(ms / 1000))
    return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
  }

  readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "") + "/walkie"

  visible: !(hideWhenIdle && (phase === "idle" || offline) && !meetingActive)
  // ACROSS the bar (height on a top/bottom bar, width on a side one) the
  // widget spans the full barSize, so `content` — which centres itself in
  // this item — lands on the bar's centre line with every sibling. ALONG the
  // bar it is content-sized, floored at the mark so it can never measure to
  // nothing.
  implicitWidth: root.vertical
    ? Math.max(root.barSize, content.implicitWidth)
    : Math.max(root.markSize, content.implicitWidth)
  implicitHeight: root.vertical
    ? Math.max(root.markSize, content.implicitHeight)
    : Math.max(root.barSize, content.implicitHeight)

  // Centre in the bar's cell rather than letting the layout decide. Without
  // this the mark sat high against its neighbours instead of on their centre
  // line (Adam, 2026-09-08). The attached property is simply ignored if a
  // section ever turns out not to be a Layout, so it is safe either way.
  Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter

  // Waybar JSON: {text, alt, class, tooltip}. class carries the phase.
  function apply(line) {
    try {
      var data = JSON.parse(line)
      root.phase = String(data.class || data.alt || "stopped")
    } catch (e) { /* keep prior state */ }
  }

  Process {
    id: statusProc
    command: ["bash", "-lc", root.walkieCmd + " status --watch"]
    stdout: SplitParser { onRead: function (line) { if (line.trim().length) root.apply(line) } }
    onExited: {
      root.phase = "stopped"
      if (!root.restartRequested) retry.interval = Math.min(retry.interval * 2, 60000)
      else { root.restartRequested = false; retry.interval = retry.baseInterval }
      retry.restart()
    }
  }
  Timer {
    id: retry
    readonly property int baseInterval: 5000
    interval: baseInterval; repeat: false
    onTriggered: if (!statusProc.running) statusProc.running = true
  }
  property bool restartRequested: false
  onWalkieCmdChanged: if (statusProc.running) refresh()
  function refresh() {
    retry.stop()
    if (statusProc.running) { root.restartRequested = true; statusProc.running = false }
    else { retry.interval = retry.baseInterval; retry.restart() }
  }
  Component.onCompleted: statusProc.running = true
  Component.onDestruction: { retry.stop(); statusProc.running = false }

  // ── runtime-state.json: meeting fields ─────────────────────────────────
  FileView {
    path: root.runtimeDir + "/runtime-state.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var d = JSON.parse(text())
        root.meetingActive = d.meeting_active === true
        root.meetingPaused = d.meeting_paused === true
        root.meetingRecordedMs = Number(d.meeting_recorded_ms || 0)
        root.stateUpdatedAt = Number(d.updated_at || 0)
        root.nextMeeting = String(d.next_meeting || "")
        root.nextMeetingLink = String(d.next_meeting_link || "")
      } catch (e) { /* ignore */ }
    }
    onLoadFailed: { root.meetingActive = false; root.nextMeeting = "" }
  }

  // ── levels file: live waveform bands (space-separated 0..100) ──────────
  property var levels: []
  property double levelsTs: 0
  readonly property bool levelsFresh: (root.nowMs - levelsTs) < 400
  FileView {
    path: root.runtimeDir + "/levels"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var parts = String(text()).trim().split(/\s+/)
      var out = []
      for (var i = 0; i < parts.length; i++) {
        var n = Number(parts[i])
        if (!isNaN(n)) out.push(Math.max(0, Math.min(100, n)))
      }
      root.levels = out
      root.levelsTs = Date.now()
    }
  }

  // ── theme colours: the backstop for `fg` ───────────────────────────────
  // Exactly the file Walkie's own UI themes from (omarchy.rs::palette_path),
  // read the same way: flat `key = "value"` lines, canonical `foreground`
  // with the legacy `fg` spelling as an alias.
  FileView {
    path: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var m = String(text()).match(/^[ \t]*(?:foreground|fg)[ \t]*=[ \t]*"?(#[0-9a-fA-F]{3,8})"?/m)
      if (m) root.paletteFg = m[1]
    }
  }

  Timer { interval: 1000; running: root.meetingActive; repeat: true; onTriggered: root.nowMs = Date.now() }
  // A faster tick keeps the waveform's freshness check and the dot blink live.
  Timer { interval: 120; running: root.meetingActive || root.dictating; repeat: true; onTriggered: root.nowMs = Date.now() }

  // Click/hover target for the whole widget, not just the mark's own pixels:
  // a 16px dot-globe is a small thing to hit in a 26px bar, and the hand
  // cursor should appear anywhere over Walkie's slot (Adam, 2026-09-08).
  // Declared BEFORE `content` on purpose — later siblings sit on top, so the
  // in-meeting play/pause control still takes its own clicks.
  MouseArea {
    id: iconMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    function launch(cmd) {
      if (root.bar && typeof root.bar.run === "function") root.bar.run(cmd)
      else Quickshell.execDetached(["bash", "-lc", cmd])
    }
    onClicked: launch(root.walkieCmd + " --open-fullscreen")
  }

  // ── presentation ──────────────────────────────────────────────────────
  GridLayout {
    id: content
    anchors.centerIn: parent
    flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
    rowSpacing: 5
    columnSpacing: 7

    // The Walkie mark — click opens Walkie full screen.
    Item {
      id: icon
      Layout.alignment: Qt.AlignCenter
      // implicitWidth/Height, NOT width/height. `content` is a GridLayout and
      // Qt Quick Layouts size their children from Layout.preferredWidth, which
      // defaults to implicitWidth — a plain Item's is 0. Setting width/height
      // here left the layout measuring a 0x0 cell and then overwriting those
      // very bindings with 0: an empty space where the mark should be
      // (Adam, 2026-09-08, after the height floor below stopped hiding it).
      implicitWidth: root.markSize
      implicitHeight: root.markSize
      // Sized from implicitWidth, not width: the dots then depend only on the
      // value this file controls, never on what the layout has assigned yet.
      // A width of 0 for one frame would otherwise draw nothing at all.
      readonly property real unit: implicitWidth / 16.0
      readonly property real dot: 1.6 * unit
      Rectangle { anchors.centerIn: parent; width: icon.dot; height: icon.dot; radius: width/2; color: root.fg; antialiasing: true }
      Repeater { model: 6; delegate: Rectangle {
        required property int index
        readonly property real a: -Math.PI/2 + index*Math.PI/3
        x: icon.implicitWidth/2 + 2.05*icon.unit*Math.cos(a) - width/2
        y: icon.implicitHeight/2 + 2.05*icon.unit*Math.sin(a) - height/2
        width: icon.dot; height: icon.dot; radius: width/2; color: root.fg; antialiasing: true } }
      Repeater { model: 12; delegate: Rectangle {
        required property int index
        readonly property real a: -Math.PI/2 + index*Math.PI/6
        x: icon.implicitWidth/2 + 4.1*icon.unit*Math.cos(a) - width/2
        y: icon.implicitHeight/2 + 4.1*icon.unit*Math.sin(a) - height/2
        width: icon.dot; height: icon.dot; radius: width/2; color: root.fg; antialiasing: true } }
      Repeater { model: 18; delegate: Rectangle {
        required property int index
        readonly property real a: -Math.PI/2 + index*Math.PI/9
        x: icon.implicitWidth/2 + 6.1*icon.unit*Math.cos(a) - width/2
        y: icon.implicitHeight/2 + 6.1*icon.unit*Math.sin(a) - height/2
        width: icon.dot; height: icon.dot; radius: width/2; color: root.fg; antialiasing: true } }
      // Match the other bar items: full foreground whenever Walkie is running.
      // Dim only when Walkie isn't running, so the mark never reads as a
      // different shade than the clock/battery beside it.
      opacity: root.offline ? 0.4 : 1.0
      Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    // Next meeting: the same line the Mac menu bar carries. Icon-only bars
    // (a vertical Omarchy bar) have no room for a sentence, so it drops out
    // there rather than wrapping.
    Text {
      Layout.alignment: Qt.AlignCenter
      Layout.maximumWidth: 220
      visible: root.showNext && !root.vertical
      text: root.nextMeeting
      elide: Text.ElideRight
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      opacity: 0.9
      MouseArea {
        anchors.fill: parent
        anchors.margins: -2
        hoverEnabled: true
        // A hand cursor only when the event HAS a link — a room booking or a
        // focus block has nothing to join, and a pointer over a dead target
        // is a lie.
        cursorShape: root.nextMeetingLink.length > 0
          ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
          if (!root.nextMeetingLink.length) return
          var cmd = "xdg-open " + JSON.stringify(root.nextMeetingLink)
          if (root.bar && typeof root.bar.run === "function") root.bar.run(cmd)
          else Quickshell.execDetached(["bash", "-lc", cmd])
        }
      }
    }

    // Dictation: a single blinking orange dot.
    Rectangle {
      Layout.alignment: Qt.AlignCenter
      visible: root.dictating && !root.meetingActive
      implicitWidth: 8; implicitHeight: 8; radius: 4; color: root.accent
      SequentialAnimation on opacity {
        running: root.dictating && !root.meetingActive
        loops: Animation.Infinite; alwaysRunToEnd: true
        NumberAnimation { to: 0.25; duration: 500 }
        NumberAnimation { to: 1.0; duration: 500 }
      }
    }

    // Meeting: live waveform + timer + play/pause. Stacks on a vertical bar,
    // and the timer text drops (icon-only convention) so it fits 28px.
    GridLayout {
      Layout.alignment: Qt.AlignCenter
      visible: root.meetingActive
      flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
      rowSpacing: 4
      columnSpacing: 6

      // The same blinking orange dot the Mac notch shows while a meeting
      // records. The dictation dot above deliberately hides during meetings,
      // so without this one a recording meeting had no "live" tell at all —
      // just a waveform, which also moves when nothing is being kept.
      // Holds STEADY while paused: a blink says "recording right now".
      Rectangle {
        Layout.alignment: Qt.AlignCenter
        implicitWidth: 8
        implicitHeight: 8
        radius: 4
        color: root.accent
        opacity: root.meetingPaused ? 0.35 : 1.0
        SequentialAnimation on opacity {
          running: root.meetingActive && !root.meetingPaused
          loops: Animation.Infinite
          alwaysRunToEnd: true
          NumberAnimation { to: 0.25; duration: 500 }
          NumberAnimation { to: 1.0; duration: 500 }
        }
      }

      Row {
        Layout.alignment: Qt.AlignCenter
        spacing: 2
        Repeater {
          model: root.vertical ? 5 : 9
          delegate: Rectangle {
            required property int index
            readonly property int count: root.vertical ? 5 : 9
            readonly property int mid: Math.floor(count / 2)
            readonly property int band: Math.round(
              (Math.abs(index - mid) / mid) * (root.levels.length - 1))
            readonly property real v: (root.meetingPaused || !root.levelsFresh || root.levels.length === 0)
              ? 0 : (root.levels[band] || 0) / 100
            width: 2
            radius: 1
            height: Math.max(2, v * (root.fontSize + 2))
            anchors.verticalCenter: parent.verticalCenter
            color: root.fg
            opacity: 0.9
            Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
          }
        }
      }

      Text {
        Layout.alignment: Qt.AlignCenter
        visible: !root.vertical
        text: root.fmt(root.meetingElapsedMs)
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
      }

      Item {
        Layout.alignment: Qt.AlignCenter
        implicitWidth: root.fontSize; implicitHeight: root.fontSize
        Row {
          anchors.centerIn: parent
          spacing: 2
          visible: !root.meetingPaused
          Rectangle { width: 2; height: root.fontSize*0.7; radius: 1; color: root.fg }
          Rectangle { width: 2; height: root.fontSize*0.7; radius: 1; color: root.fg }
        }
        Canvas {
          anchors.centerIn: parent
          width: root.fontSize*0.8; height: root.fontSize*0.8
          visible: root.meetingPaused
          onPaint: {
            var ctx = getContext("2d"); ctx.reset()
            ctx.fillStyle = root.fg
            ctx.beginPath(); ctx.moveTo(1, 0); ctx.lineTo(width-1, height/2); ctx.lineTo(1, height); ctx.closePath(); ctx.fill()
          }
        }
        MouseArea {
          anchors.fill: parent
          anchors.margins: -3
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            var cmd = root.walkieCmd + " --toggle-meeting-pause"
            if (root.bar && typeof root.bar.run === "function") root.bar.run(cmd)
            else Quickshell.execDetached(["bash", "-lc", cmd])
          }
        }
      }
    }
  }
}
