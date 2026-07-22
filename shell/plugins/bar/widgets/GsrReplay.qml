import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.gsr-replay"

  property string replayState: "inactive"
  property string replayTooltip: "Replay buffer is off"

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function runAction(command) {
    if (!root.bar) return
    root.bar.run(command)
    refreshTimer.restart()
  }

  Component.onCompleted: refresh()
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: statusProc
    command: ["/usr/bin/gsr-replay", "status-json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var status = JSON.parse(String(text || "{}"))
          root.replayState = String(status.alt || "inactive")
          root.replayTooltip = String(status.tooltip || "Replay buffer is off")
        } catch (error) {
          root.replayState = "failed"
          root.replayTooltip = "GSR Replay status unavailable"
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.replayState = "failed"
        root.replayTooltip = "GSR Replay status unavailable"
      }
    }
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: refreshTimer
    interval: 500
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "REC"
    active: root.replayState === "active"
    fontSize: Style.font.caption
    horizontalMargin: 6
    tooltipText: root.replayTooltip
    onPressed: function(button) {
      if (button === Qt.RightButton) root.runAction("omarchy-capture-replay toggle")
      else root.runAction("omarchy-capture-replay save")
    }
  }
}
