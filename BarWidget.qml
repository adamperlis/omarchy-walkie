// Walkie — Omarchy bar widget.
//
// Streams `walkie status --watch` (one JSON line per state change) and renders
// the current phase: idle, recording, analyzing, transcribing, thinking,
// speaking, error, meeting, or stopped when Walkie is not running.
//
// Deliberately depends on QtQuick + Quickshell.Io ONLY — not on `qs.Ui` or
// `qs.Commons`. Those modules live inside $OMARCHY_PATH/shell and are versioned
// with Omarchy, not with this plugin, so importing them would make the widget
// break on an Omarchy upgrade. Everything below is the documented version-proof
// baseline from shell/plugins/bar/README.md: an Item with implicitWidth /
// implicitHeight that reads colors off the injected `bar`.
//
// The bar injects three properties AFTER construction (bar, moduleName,
// settings), so nothing here may assume `bar` is non-null at load time.
// One instance exists per monitor, so one status process runs per screen.

import QtQuick
import Quickshell.Io

Item {
  id: root

  // ── injected by the bar host ───────────────────────────────────────────
  property QtObject bar: null
  property string moduleName: ""
  property var settings: ({})

  // ── config (from the shell.json layout entry) ─────────────────────────
  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return (value === undefined || value === null) ? fallback : value
  }
  readonly property string walkieCmd: String(setting("command", "walkie"))
  readonly property bool hideWhenIdle: setting("hideWhenIdle", false) === true
  readonly property bool showLabel: setting("showLabel", false) === true
  // The bar's own font carries the Nerd Font glyphs; a plugin Loader does not
  // propagate it, so inherit explicitly and let the user override.
  // Empty string counts as "unset": `setting()` only falls back on
  // undefined/null, and the manifest's documented default is "".
  readonly property string fontFamily: {
    var chosen = String(setting("fontFamily", ""))
    if (chosen) return chosen
    return root.bar && root.bar.fontFamily ? root.bar.fontFamily : "monospace"
  }
  readonly property int fontSize: Number(setting("fontSize", 14))

  // ── brand mark ────────────────────────────────────────────────────────
  // The bar draws the HUB of the Walkie dot-globe: the centre dot and its
  // inner ring of six. The full mark is ~131 dots — at the bar's 16px it
  // reduced to noise however few rings were kept (field-verified on a
  // default-size vertical bar, Adam 2026-09-04), and a painted Canvas
  // blurred on scaled displays besides. Seven scene-graph circles stay
  // crisp at any DPR, tint with the theme, and read as Walkie at a glance.
  // Deliberately the brand mark, not a Nerd Font mic: Omarchy's Voxtype
  // already puts a mic in the bar (Adam, 2026-09-03/04).
  // Geometry in 16ths of the box: ring radius 5.2, dot radius 1.6 — the
  // farthest extent is 6.8/8, so the recording breath (scale 1.15) still
  // never touches the edge.

  // U+F036 followed by the letter "d". Only used until the first status line
  // arrives and when the stream dies; every other glyph comes from the
  // `text` field of `walkie status`.
  //
  // Lower-case initial letter is mandatory: QML rejects property names that
  // begin with an upper case letter (qqmlirbuilder.cpp), and it is a parse
  // error that fails the WHOLE component, not just the property — the widget
  // would silently never load, with nothing in `omarchy plugin validate` to
  // catch it since that validator does not parse QML.
  readonly property string micOffGlyph: "\uDB80\uDF6D"

  property string phase: "stopped"
  property string glyph: micOffGlyph
  property string tip: "Walkie"

  readonly property bool busy: phase === "analyzing" || phase === "transcribing"
                               || phase === "thinking" || phase === "speaking"
  readonly property bool active: phase === "recording" || phase === "meeting" || busy
  readonly property bool offline: phase === "stopped"

  // Bar.showTooltip() silently drops the request unless the target exposes
  // `tooltipHovered === true` (Bar.qml targetTooltipHovered). qs.Ui's
  // WidgetButton provides it; a plain Item must declare it itself.
  readonly property bool tooltipHovered: visible && mouse.containsMouse

  // The bar slot sizes itself from these; both must be finite and >= 0.
  readonly property bool vertical: bar ? bar.vertical === true : false
  visible: !(hideWhenIdle && (phase === "idle" || offline))
  implicitWidth: visible ? (vertical ? (bar ? bar.barSize : 24) : content.implicitWidth + 12) : 0
  implicitHeight: visible ? (vertical ? content.implicitHeight + 12 : (bar ? bar.barSize : 24)) : 0

  // ── parsing ───────────────────────────────────────────────────────────
  // `walkie status` emits Waybar-shaped JSON: {text, alt, class, tooltip}.
  // `class` is the stable field; `text` is a Nerd Font glyph we render as-is.
  // Anything unparseable leaves the previous state alone rather than blanking
  // the widget — a malformed line should never look like "Walkie crashed".
  function apply(line) {
    var raw = String(line || "").trim()
    if (!raw) return
    var data
    try {
      data = JSON.parse(raw)
    } catch (e) {
      return
    }
    if (!data || typeof data !== "object") return
    retry.interval = retry.baseInterval
    root.phase = String(data.class || data.alt || "stopped")
    root.glyph = data.text ? String(data.text) : root.glyph
    root.tip = data.tooltip ? String(data.tooltip) : "Walkie"
  }

  // ── status stream ─────────────────────────────────────────────────────
  Process {
    id: statusProc
    command: ["bash", "-lc", root.walkieCmd + " status --watch"]
    running: false
    stdout: SplitParser {
      onRead: function (line) { root.apply(line) }
    }
    onExited: function (exitCode, exitStatus) {
      // Reached when Walkie is not installed, the command errored, or the
      // stream ended. NEVER respawn immediately: this runs inside the
      // long-lived Omarchy shell process, and a hot restart loop on a missing
      // binary would degrade the whole desktop.
      if (!root.restartRequested) {
        root.phase = "stopped"
        root.glyph = root.micOffGlyph
        root.tip = "Walkie is not running"
        // Back off on repeated failure (missing binary, wrong `command`) so a
        // permanently broken config settles at one probe a minute rather than
        // twelve.
        retry.interval = Math.min(retry.interval * 2, 60000)
      } else {
        root.restartRequested = false
        retry.interval = retry.baseInterval
      }
      retry.restart()
    }
  }

  Timer {
    id: retry
    readonly property int baseInterval: 5000
    interval: baseInterval
    repeat: false
    onTriggered: if (!statusProc.running) statusProc.running = true
  }

  // Set while a restart is deliberate, so onExited treats the exit as
  // requested rather than as a failure to back off from.
  property bool restartRequested: false

  // Restart the stream if the user edits `command` in shell.json. Skipped
  // during construction — Component.onCompleted does the initial start, and
  // restarting a process that has not launched yet would be a no-op that
  // leaves the widget dead.
  onWalkieCmdChanged: if (statusProc.running) refresh()

  // Optional widget-contract hook; must not throw.
  function refresh() {
    retry.stop()
    if (statusProc.running) {
      // `running = false` only sends SIGTERM; the relaunch happens in
      // onExited once the process has actually gone.
      root.restartRequested = true
      statusProc.running = false
    } else {
      retry.interval = retry.baseInterval
      retry.restart()
    }
  }

  Component.onCompleted: statusProc.running = true
  Component.onDestruction: {
    retry.stop()
    statusProc.running = false
  }

  // ── presentation ──────────────────────────────────────────────────────
  Row {
    id: content
    anchors.centerIn: parent
    spacing: 6

    Item {
      id: icon
      anchors.verticalCenter: parent.verticalCenter
      width: root.fontSize + 2
      height: root.fontSize + 2

      readonly property color fill: root.bar ? root.bar.foreground : "white"
      readonly property real unit: width / 16.0
      readonly property real dot: 3.2 * unit

      Rectangle {
        anchors.centerIn: parent
        width: icon.dot
        height: icon.dot
        radius: width / 2
        color: icon.fill
        antialiasing: true
      }
      Repeater {
        model: 6
        delegate: Rectangle {
          required property int index
          readonly property real angle: -Math.PI / 2 + index * Math.PI / 3
          x: icon.width / 2 + 5.2 * icon.unit * Math.cos(angle) - width / 2
          y: icon.height / 2 + 5.2 * icon.unit * Math.sin(angle) - height / 2
          width: icon.dot
          height: icon.dot
          radius: width / 2
          color: icon.fill
          antialiasing: true
        }
      }

      // Idle and offline recede; anything happening reads at full strength.
      opacity: root.active ? 1.0 : (root.offline ? 0.35 : 0.6)
      Behavior on opacity { NumberAnimation { duration: 150 } }

      // A slow breath while the mic is open — the one state worth noticing
      // from across the room. Stops completely otherwise, so an idle bar
      // costs nothing.
      SequentialAnimation on scale {
        running: root.phase === "recording"
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { to: 1.15; duration: 650; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 1.0; duration: 650; easing.type: Easing.InOutQuad }
      }
      onVisibleChanged: if (!visible) scale = 1.0
    }

    Text {
      visible: root.showLabel && root.phase !== "idle" && !root.offline
      anchors.verticalCenter: parent.verticalCenter
      text: root.phase
      color: root.bar ? root.bar.foreground : "white"
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      opacity: 0.8
    }
  }

  // ── interaction ───────────────────────────────────────────────────────
  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    // Left  — open / focus Walkie. A bare left click starting the
    //         MICROPHONE was too loud an action for the bar's quietest
    //         gesture (Adam, 2026-09-04); Omarchy's own widgets open
    //         panels on left click, never fire state changes.
    // Right — toggle dictation (start, then stop and transcribe)
    // Middle— cancel whatever is running
    onClicked: function (mouse) {
      if (!root.bar || typeof root.bar.run !== "function") return
      // Walkie not running: every button just launches it. Toggling a
      // recorder that isn't there did nothing and read as broken
      // (Adam, 2026-09-03).
      if (root.offline) { root.bar.run(root.walkieCmd); return }
      if (mouse.button === Qt.RightButton) root.bar.run(root.walkieCmd + " --toggle-transcription")
      else if (mouse.button === Qt.MiddleButton) root.bar.run(root.walkieCmd + " --cancel")
      else root.bar.run(root.walkieCmd)
    }

    onEntered: if (root.bar && typeof root.bar.showTooltip === "function") root.bar.showTooltip(root, root.tip)
    onExited: if (root.bar && typeof root.bar.hideTooltip === "function") root.bar.hideTooltip(root)
  }
}
