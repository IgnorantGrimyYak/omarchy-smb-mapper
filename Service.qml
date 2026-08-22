import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root
  property string moduleName: "io.github.bmontythe3rd.smb-mapper"
  property string helperPath: Model.helperPathFromUrl(Qt.resolvedUrl("bin/smb-mapper"))
  property bool started: false

  function automount() {
    if (mountProc.running)
      return
    mountProc.command = [helperPath, "automount"]
    mountProc.running = true
  }

  Component.onCompleted: startTimer.start()

  Timer {
    id: startTimer
    interval: 4000
    repeat: false
    onTriggered: root.automount()
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: if (root.started) root.automount()
  }

  Process {
    id: mountProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseOutput(text)
        if (!parsed || parsed.ok !== true)
          return
        root.started = true
        var mounted = parsed.mounted || []
        for (var i = 0; i < mounted.length; i++) {
          var share = mounted[i]
          Quickshell.execDetached([
            "omarchy-notification-send",
            "-g",
            "󰉌",
            "SMB drive connected",
            share.label + " is available in ~/Shares/" + share.label
          ])
        }
      }
    }
    stderr: StdioCollector { id: mountError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0)
        console.warn("SMB automount failed" + (mountError.text ? ": " + mountError.text : ""))
    }
  }
}
