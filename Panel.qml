import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Walkie's bar panel — summoned by the bar widget (left click), closed by
// Escape, click-outside, or clicking the widget again.
//
// Deliberately split from BarWidget.qml: the widget stays dependency-free
// so a shell upgrade that moves qs.Commons/qs.Ui can only break this panel,
// never the bar icon. Data comes from the same runtime-state.json the
// widget reads; the full last-dictation text never enters the file — the
// copy action asks the app itself (`walkie --copy-last`).
Item {
  id: root

  // Summon payload: {"command": "<walkie executable>"} — the widget passes
  // its configured command through so AppImage installs keep working.
  property string command: "walkie"

  property var state: null
  property double nowMs: Date.now()
  property bool copiedFlash: false

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property string statePath: runtimeDir + "/walkie/runtime-state.json"

  readonly property bool running: state !== null
  readonly property string phase: running ? String(state.phase || "idle") : "idle"
  readonly property bool recording: phase === "recording"
  readonly property bool busy: phase === "transcribing" || phase === "analyzing"
      || phase === "thinking" || phase === "speaking"
  readonly property bool meetingActive: running && state.meeting_active === true
  readonly property bool meetingPaused: running && state.meeting_paused === true

  readonly property color fg: Color.foreground
  readonly property color dim: Qt.darker(fg, 1.55)
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent

  function fmtElapsed(ms) {
    var s = Math.max(0, Math.floor(ms / 1000))
    var m = Math.floor(s / 60)
    return m + ":" + String(s % 60).padStart(2, "0")
  }

  // Dictation clock: phase flips stamp phase_since.
  readonly property string dictationClock:
    recording && state.phase_since ? fmtElapsed(nowMs - Number(state.phase_since)) : ""

  // Meeting clock: recorded ms at last write, advancing while un-paused.
  readonly property string meetingClock: {
    if (!meetingActive) return ""
    var base = Number(state.meeting_recorded_ms || 0)
    if (!meetingPaused && state.updated_at) base += Math.max(0, nowMs - Number(state.updated_at))
    return fmtElapsed(base)
  }

  readonly property string stateLabel: {
    if (!running) return "Not running"
    if (recording) return "Recording"
    if (busy) return "Working"
    if (phase === "error") return "Error"
    return "Ready"
  }
  readonly property color stateColor: {
    if (!running) return dim
    if (recording) return urgent
    if (busy || phase === "error") return accent
    return fg
  }

  readonly property string lastText: running && state.last_text ? String(state.last_text) : ""
  readonly property string lastAgo: {
    if (!running || !state.last_text_at) return ""
    var mins = Math.floor((nowMs - Number(state.last_text_at)) / 60000)
    if (mins < 1) return "just now"
    if (mins < 60) return mins + "m ago"
    var hrs = Math.floor(mins / 60)
    return hrs < 24 ? hrs + "h ago" : Math.floor(hrs / 24) + "d ago"
  }

  readonly property double hoursLeft: running && state.hours_left !== null
      && state.hours_left !== undefined ? Number(state.hours_left) : -1
  readonly property bool lowHours: hoursLeft >= 0 && hoursLeft < 2

  function run(cmd) { Quickshell.execDetached(["bash", "-lc", cmd]) }
  function close() { run("omarchy-shell shell hide com.b150.walkie") }

  FileView {
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.state = JSON.parse(text()) } catch (e) { root.state = null }
    }
    onLoadFailed: root.state = null
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Timer {
    id: copiedTimer
    interval: 1400
    onTriggered: root.copiedFlash = false
  }

  PanelWindow {
    id: panel
    visible: true
    anchors { top: true; right: true }
    margins { top: Style.space(8); right: Style.space(8) }
    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight
    color: "transparent"
    WlrLayershell.namespace: "walkie-panel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    Keys.onEscapePressed: root.close()

    HyprlandFocusGrab {
      windows: [panel]
      active: true
      onCleared: root.close()
    }

    BorderSurface {
      id: card
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, 2)
      padding: Style.space(14)
      implicitWidth: content.implicitWidth + card.contentLeftInset + card.contentRightInset
      implicitHeight: content.implicitHeight + card.contentTopInset + card.contentBottomInset

      ColumnLayout {
        id: content
        x: card.contentLeftInset
        y: card.contentTopInset
        width: Style.space(280)
        spacing: Style.space(10)

        // Header: state + live clock
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)
          Rectangle {
            width: Style.space(8); height: Style.space(8); radius: width / 2
            color: root.stateColor
            SequentialAnimation on opacity {
              running: root.recording
              loops: Animation.Infinite
              NumberAnimation { from: 1; to: 0.35; duration: 700 }
              NumberAnimation { from: 0.35; to: 1; duration: 700 }
            }
          }
          Text {
            text: root.stateLabel
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.size(13)
            font.weight: Font.DemiBold
          }
          Item { Layout.fillWidth: true }
          Text {
            visible: root.dictationClock !== ""
            text: root.dictationClock
            color: root.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.size(13)
          }
        }

        // Meeting row, only while one records
        RowLayout {
          visible: root.meetingActive
          Layout.fillWidth: true
          spacing: Style.space(8)
          Text {
            text: root.meetingPaused ? "Meeting paused" : "Meeting recording"
            color: root.meetingPaused ? root.dim : root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.size(12)
          }
          Item { Layout.fillWidth: true }
          Text {
            text: root.meetingClock
            color: root.meetingPaused ? root.dim : root.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.size(12)
          }
        }

        // Last dictation + copy
        ColumnLayout {
          visible: root.lastText !== ""
          Layout.fillWidth: true
          spacing: Style.space(4)
          RowLayout {
            Layout.fillWidth: true
            Text {
              text: "LAST DICTATION"
              color: root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.size(9)
              font.letterSpacing: 1
            }
            Item { Layout.fillWidth: true }
            Text {
              text: root.copiedFlash ? "Copied" : root.lastAgo
              color: root.copiedFlash ? root.accent : root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.size(9)
            }
          }
          Text {
            Layout.fillWidth: true
            text: root.lastText
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.size(12)
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
          }
          Rectangle {
            Layout.fillWidth: true
            implicitHeight: copyLabel.implicitHeight + Style.space(10)
            radius: Style.space(6)
            color: copyArea.containsMouse ? Qt.alpha(root.fg, 0.12) : Qt.alpha(root.fg, 0.06)
            Text {
              id: copyLabel
              anchors.centerIn: parent
              text: "Copy"
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.size(12)
            }
            MouseArea {
              id: copyArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.run(root.command + " --copy-last")
                root.copiedFlash = true
                copiedTimer.restart()
              }
            }
          }
        }

        // Actions
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)
          Rectangle {
            Layout.fillWidth: true
            implicitHeight: dictateLabel.implicitHeight + Style.space(12)
            radius: Style.space(6)
            color: dictateArea.containsMouse ? Qt.alpha(root.accent, 0.28) : Qt.alpha(root.accent, 0.18)
            Text {
              id: dictateLabel
              anchors.centerIn: parent
              text: root.running
                  ? (root.recording ? "Stop & transcribe" : "Start dictation")
                  : "Open Walkie"
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.size(12)
              font.weight: Font.DemiBold
            }
            MouseArea {
              id: dictateArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.run(root.running ? root.command + " --toggle-transcription" : root.command)
                root.close()
              }
            }
          }
          Rectangle {
            visible: root.running
            Layout.fillWidth: true
            implicitHeight: openLabel.implicitHeight + Style.space(12)
            radius: Style.space(6)
            color: openArea.containsMouse ? Qt.alpha(root.fg, 0.12) : Qt.alpha(root.fg, 0.06)
            Text {
              id: openLabel
              anchors.centerIn: parent
              text: "Open Walkie"
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.size(12)
            }
            MouseArea {
              id: openArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { root.run(root.command); root.close() }
            }
          }
        }

        // Low-hours footer — present exactly when it matters
        Text {
          visible: root.lowHours
          Layout.fillWidth: true
          text: root.hoursLeft <= 0
              ? "Meeting hours used up for this month"
              : root.hoursLeft.toFixed(1) + " meeting hours left this month"
          color: root.hoursLeft <= 0 ? root.urgent : root.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.size(10)
        }
      }
    }
  }
}
