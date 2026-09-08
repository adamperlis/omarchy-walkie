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

  property QtObject bar: null
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
  readonly property int fontSize: Number(setting("fontSize", 14))
  readonly property color fg: root.bar ? root.bar.foreground : "white"
  readonly property color accent: "#fb4501"
  // Omarchy exposes bar.position; on a left/right (vertical) bar, widgets fall
  // back to a compact icon-only form (shell/plugins/bar/README.md).
  readonly property bool vertical: root.bar
    && (String(root.bar.position) === "left" || String(root.bar.position) === "right")

  // ── phase / offline (Waybar-shaped stream) ─────────────────────────────
  property string phase: "stopped"
  readonly property bool busy: phase === "analyzing" || phase === "transcribing"
                               || phase === "thinking" || phase === "speaking"
  readonly property bool dictating: phase === "recording"
  readonly property bool offline: phase === "stopped"

  // ── richer state from runtime-state.json ───────────────────────────────
  property bool meetingActive: false
  property bool meetingPaused: false
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
  implicitWidth: content.implicitWidth
  implicitHeight: Math.max(fontSize + 6, content.implicitHeight)

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
      } catch (e) { /* ignore */ }
    }
    onLoadFailed: root.meetingActive = false
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

  Timer { interval: 1000; running: root.meetingActive; repeat: true; onTriggered: root.nowMs = Date.now() }
  // A faster tick keeps the waveform's freshness check and the dot blink live.
  Timer { interval: 120; running: root.meetingActive || root.dictating; repeat: true; onTriggered: root.nowMs = Date.now() }

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
      width: root.fontSize + 2
      height: root.fontSize + 2
      readonly property real unit: width / 16.0
      readonly property real dot: 1.6 * unit
      Rectangle { anchors.centerIn: parent; width: icon.dot; height: icon.dot; radius: width/2; color: root.fg; antialiasing: true }
      Repeater { model: 6; delegate: Rectangle {
        required property int index
        readonly property real a: -Math.PI/2 + index*Math.PI/3
        x: icon.width/2 + 2.05*icon.unit*Math.cos(a) - width/2
        y: icon.height/2 + 2.05*icon.unit*Math.sin(a) - height/2
        width: icon.dot; height: icon.dot; radius: width/2; color: root.fg; antialiasing: true } }
      Repeater { model: 12; delegate: Rectangle {
        required property int index
        readonly property real a: -Math.PI/2 + index*Math.PI/6
        x: icon.width/2 + 4.1*icon.unit*Math.cos(a) - width/2
        y: icon.height/2 + 4.1*icon.unit*Math.sin(a) - height/2
        width: icon.dot; height: icon.dot; radius: width/2; color: root.fg; antialiasing: true } }
      Repeater { model: 18; delegate: Rectangle {
        required property int index
        readonly property real a: -Math.PI/2 + index*Math.PI/9
        x: icon.width/2 + 6.1*icon.unit*Math.cos(a) - width/2
        y: icon.height/2 + 6.1*icon.unit*Math.sin(a) - height/2
        width: icon.dot; height: icon.dot; radius: width/2; color: root.fg; antialiasing: true } }
      opacity: (root.meetingActive || root.dictating || iconMouse.containsMouse) ? 1.0 : (root.offline ? 0.35 : 0.6)
      Behavior on opacity { NumberAnimation { duration: 150 } }
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
    }

    // Dictation: a single blinking orange dot.
    Rectangle {
      Layout.alignment: Qt.AlignCenter
      visible: root.dictating && !root.meetingActive
      width: 8; height: 8; radius: 4; color: root.accent
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
        width: root.fontSize; height: root.fontSize
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
