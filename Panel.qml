import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.bmontythe3rd.smb-mapper"
  ipcTarget: moduleName

  property var shares: []
  property var doctor: ({})
  property var form: Model.emptyForm()
  property var browseResults: []
  property var failure: ({ id: "", message: "" })
  property string helperPath: Model.helperPathFromUrl(Qt.resolvedUrl("bin/smb-mapper"))
  property string statusMessage: ""
  property string busyId: ""
  property string busyKind: ""
  property string pendingPayload: ""
  property string focusSection: "header"
  property int selectedIndex: 0
  property bool loading: false
  property bool editing: false
  property bool browsing: false
  property bool cursorActive: false

  readonly property int mountedCount: Model.mountedCount(shares)
  readonly property string doctorHint: Model.doctorHint(doctor)
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property bool busy: busyKind !== ""
  readonly property bool formComplete: form.host.length > 0 && form.share.length > 0 && (form.guest || form.username.length > 0)

  function parseOutput(text) {
    return Model.parseOutput(text)
  }

  function processError(text, fallback) {
    return Model.processError(text, fallback)
  }

  function runHelper(kind, args, payload, shareId) {
    if (actionProc.running)
      return
    busyKind = kind
    busyId = shareId || ""
    failure = { id: "", message: "" }
    pendingPayload = payload ? JSON.stringify(payload) : ""
    var command = [helperPath, kind]
    for (var i = 0; i < (args || []).length; i++)
      command.push(args[i])
    actionProc.command = command
    actionProc.stdinEnabled = pendingPayload !== ""
    actionProc.running = true
  }

  function refresh() {
    if (listProc.running)
      return
    loading = true
    listProc.command = [helperPath, "list"]
    listProc.running = true
  }

  function saveForm() {
    if (!formComplete || busy)
      return
    var payload = Model.requestPayload(form)
    if (form.id)
      runHelper("update", [form.id], payload, form.id)
    else
      runHelper("add", [], payload, "")
  }

  function mountShare(share) {
    if (!share || busy)
      return
    var payload = {}
    if (form.id === share.id && form.password)
      payload.password = form.password
    runHelper("mount", [share.id], Object.keys(payload).length ? payload : null, share.id)
  }

  function unmountShare(share) {
    if (!share || busy)
      return
    runHelper("unmount", [share.id], null, share.id)
  }

  function toggleShare(share) {
    if (!share)
      return
    if (share.mounted)
      unmountShare(share)
    else
      mountShare(share)
  }

  function removeShare(share) {
    if (!share || busy)
      return
    runHelper("remove", [share.id], null, share.id)
  }

  function openShare(share) {
    if (!share)
      return
    var target = share.uri || share.mountPath || share.path
    if (!target)
      return
    if (!share.mounted && !share.mountPath)
      return
    // Detach through uwsm so Files outlives the panel process, and prefer the
    // smb:// URI because GVFS fuse paths often fail Path.exists() / xdg-open.
    Quickshell.execDetached(["uwsm-app", "--", "nautilus", "--new-window", target])
  }

  function browseShares() {
    if (!form.host || browseProc.running)
      return
    browsing = true
    browseProc.stdinEnabled = true
    browseProc.command = [helperPath, "browse"]
    pendingPayload = JSON.stringify(Model.requestPayload(form))
    browseProc.running = true
  }

  function startAdd() {
    form = Model.emptyForm()
    browseResults = []
    editing = true
    statusMessage = ""
    Qt.callLater(function() { if (hostField) hostField.forceActiveFocus() })
  }

  function startEdit(share) {
    form = Model.formFromShare(share)
    browseResults = []
    editing = true
    Qt.callLater(function() { if (hostField) hostField.forceActiveFocus() })
  }

  function cancelEdit() {
    form = Model.emptyForm()
    browseResults = []
    editing = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function selectByDelta(delta) {
    if (shares.length === 0) {
      selectedIndex = 0
      return
    }
    selectedIndex = Math.max(0, Math.min(shares.length - 1, selectedIndex + delta))
  }

  function selectedShare() {
    if (selectedIndex < 0 || selectedIndex >= shares.length)
      return null
    return shares[selectedIndex]
  }

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) refresh()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.barIcon(root.mountedCount)
    tooltipText: Model.barTooltip(root.mountedCount, root.shares.length)
    active: root.mountedCount > 0
    onPressed: function() { root.toggle() }
  }

  Process {
    id: listProc
    property bool outputValid: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = root.parseOutput(text)
        if (parsed && parsed.ok) {
          listProc.outputValid = true
          root.shares = parsed.shares || []
          root.doctor = parsed.doctor || {}
          if (root.selectedIndex >= root.shares.length)
            root.selectedIndex = Math.max(0, root.shares.length - 1)
        }
      }
    }
    stderr: StdioCollector { id: listError; waitForEnd: true }
    onRunningChanged: if (running) outputValid = false
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode !== 0 || !outputValid)
        root.statusMessage = root.processError(listError.text, "Could not read saved SMB shares")
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { id: actionOutput; waitForEnd: true }
    stderr: StdioCollector { id: actionError; waitForEnd: true }
    onStarted: {
      if (root.pendingPayload !== "") {
        write(root.pendingPayload + "\n")
        root.pendingPayload = ""
        stdinEnabled = false
      }
    }
    onExited: function(exitCode) {
      var kind = root.busyKind
      var shareId = root.busyId
      root.busyKind = ""
      root.busyId = ""
      if (exitCode === 0) {
        root.form = Model.setFormField(root.form, "password", "")
        if (kind === "add" || kind === "update") {
          root.editing = false
          root.statusMessage = kind === "add" ? "Share saved" : "Share updated"
        } else if (kind === "remove") {
          root.statusMessage = "Share removed"
        }
        root.refresh()
      } else {
        root.failure = {
          id: shareId,
          message: root.processError(actionError.text, "Could not complete that action")
        }
        root.statusMessage = root.failure.message
      }
    }
  }

  Process {
    id: browseProc
    stdout: StdioCollector { id: browseOutput; waitForEnd: true }
    stderr: StdioCollector { id: browseError; waitForEnd: true }
    onStarted: {
      if (root.pendingPayload !== "") {
        write(root.pendingPayload + "\n")
        root.pendingPayload = ""
        stdinEnabled = false
      }
    }
    onExited: function(exitCode) {
      root.browsing = false
      if (exitCode === 0) {
        var parsed = root.parseOutput(browseOutput.text)
        root.browseResults = parsed && parsed.shares ? parsed.shares : []
        root.statusMessage = root.browseResults.length ? "" : "No folders were advertised on that server"
      } else {
        root.browseResults = []
        root.statusMessage = root.processError(browseError.text, "Could not browse that server")
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editing
      onMoveRequested: function(dx, dy) {
        root.cursorActive = true
        if (dy !== 0)
          root.selectByDelta(dy)
      }
      onActivateRequested: {
        var share = root.selectedShare()
        if (share)
          root.toggleShare(share)
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "n" || t === "N")
          root.startAdd()
        else if (t === "r" || t === "R")
          root.refresh()
        else if (t === "o" || t === "O") {
          var share = root.selectedShare()
          if (share)
            root.openShare(share)
        }
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, addButton.implicitHeight)

          Text {
            id: heroIcon
            text: Model.barIcon(root.mountedCount)
            color: root.mountedCount > 0 ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: addButton.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: "SMB Drives"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: Model.heroMeta(root.mountedCount, root.shares.length)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
            }
          }

          Button {
            id: addButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.editing ? "Close" : "Add"
            tooltipText: root.editing ? "Close the share form" : "Save a new SMB share"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(10)
            verticalPadding: Style.space(4)
            bordered: true
            onClicked: root.editing ? root.cancelEdit() : root.startAdd()
          }
        }

        Text {
          width: parent.width
          visible: root.doctorHint !== ""
          text: root.doctorHint
          wrapMode: Text.WordWrap
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          visible: root.statusMessage !== "" && root.doctorHint === ""
          text: root.statusMessage
          wrapMode: Text.WordWrap
          color: root.failure.message ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Column {
          visible: root.editing
          width: parent.width
          spacing: Style.space(8)

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: root.form.id ? "EDIT SHARE" : "ADD SHARE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          TextField {
            id: hostField
            width: parent.width
            placeholderText: "Server"
            text: root.form.host
            foreground: root.foreground
            enabled: !root.busy
            onTextChanged: if (text !== root.form.host) root.form = Model.setFormField(root.form, "host", text)
            Keys.onEscapePressed: root.cancelEdit()
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: shareField
              width: parent.width - browseButton.width - parent.spacing
              placeholderText: "Share name"
              text: root.form.share
              foreground: root.foreground
              enabled: !root.busy
              onTextChanged: if (text !== root.form.share) root.form = Model.setFormField(root.form, "share", text)
              Keys.onEscapePressed: root.cancelEdit()
            }

            Button {
              id: browseButton
              text: root.browsing ? "…" : "Browse"
              tooltipText: "List folders advertised by this server"
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              enabled: root.form.host.length > 0 && !root.busy
              bordered: true
              onClicked: root.browseShares()
            }
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)
            visible: root.browseResults.length > 0

            Repeater {
              model: root.browseResults
              delegate: Button {
                required property string modelData
                text: modelData
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                bordered: true
                selected: root.form.share === modelData
                onClicked: root.form = Model.setFormField(root.form, "share", modelData)
              }
            }
          }

          TextField {
            width: parent.width
            placeholderText: "Label (optional)"
            text: root.form.label
            foreground: root.foreground
            enabled: !root.busy
            onTextChanged: if (text !== root.form.label) root.form = Model.setFormField(root.form, "label", text)
            Keys.onEscapePressed: root.cancelEdit()
          }

          TextField {
            width: parent.width
            visible: !root.form.guest
            placeholderText: "Username"
            text: root.form.username
            foreground: root.foreground
            enabled: !root.busy
            onTextChanged: if (text !== root.form.username) root.form = Model.setFormField(root.form, "username", text)
            Keys.onEscapePressed: root.cancelEdit()
          }

          TextField {
            width: parent.width
            visible: !root.form.guest
            placeholderText: "Domain (optional)"
            text: root.form.domain
            foreground: root.foreground
            enabled: !root.busy
            onTextChanged: if (text !== root.form.domain) root.form = Model.setFormField(root.form, "domain", text)
            Keys.onEscapePressed: root.cancelEdit()
          }

          TextField {
            width: parent.width
            visible: !root.form.guest
            password: true
            placeholderText: root.form.id ? "Password (leave blank to keep saved)" : "Password"
            text: root.form.password
            foreground: root.foreground
            enabled: !root.busy
            onTextChanged: if (text !== root.form.password) root.form = Model.setFormField(root.form, "password", text)
            onAccepted: root.saveForm()
            Keys.onEscapePressed: root.cancelEdit()
          }

          Toggle {
            width: parent.width
            label: "Guest access"
            description: "Connect without a username or saved password"
            checked: root.form.guest
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.form = Model.setFormField(root.form, "guest", !root.form.guest)
          }

          Toggle {
            width: parent.width
            label: "Connect automatically"
            description: "Mount this share when Omarchy starts"
            checked: root.form.automount
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.form = Model.setFormField(root.form, "automount", !root.form.automount)
          }

          Button {
            width: parent.width
            text: root.busyKind === "add" || root.busyKind === "update" ? "Saving…" : "Save share"
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            enabled: root.formComplete && !root.busy
            onClicked: root.saveForm()
          }
        }

        PanelSeparator {
          visible: !root.editing
          foreground: root.foreground
        }

        PanelSectionHeader {
          visible: !root.editing
          text: root.shares.length ? "SAVED SHARES" : "NO SAVED SHARES"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Text {
          visible: !root.editing && root.shares.length === 0
          width: parent.width
          text: "Add a server and share name to map it into ~/Shares. Passwords are stored in the system keyring, not in the plugin config."
          wrapMode: Text.WordWrap
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        ListView {
          id: shareList
          visible: !root.editing && root.shares.length > 0
          width: parent.width
          height: Math.min(contentHeight, Style.space(280))
          spacing: Style.space(4)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          model: root.shares
          currentIndex: root.selectedIndex
          onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

          delegate: Item {
            required property var modelData
            required property int index
            width: ListView.view.width
            height: row.implicitHeight

            ShareRow {
              id: row
              width: parent.width
              share: modelData
              index: parent.index
            }
          }
        }
      }
    }
  }

  component ShareRow: CursorSurface {
    id: row
    required property var share
    required property int index

    readonly property bool isSelected: root.selectedIndex === index
    readonly property string statusText: Model.statusLabel(share, root.busyId, root.busyKind, root.failure)
    readonly property color statusColor: {
      if (root.failure.id === (share ? share.id : "") && root.failure.message)
        return root.urgent
      if (share && share.mounted)
        return root.foreground
      return root.dim
    }

    hasCursor: root.cursorActive && isSelected
    current: !!(share && share.mounted)
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: body.implicitHeight

    MouseArea {
      anchors.fill: parent
      z: -1
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.selectedIndex = row.index
      }
      onClicked: root.toggleShare(row.share)
    }

    Item {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      implicitHeight: Math.max(iconLabel.implicitHeight, info.implicitHeight, actions.implicitHeight) + Style.spacing.rowPaddingX

      Text {
        id: iconLabel
        text: row.share && row.share.mounted ? "󰉌" : "󰉍"
        color: row.statusColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Row {
        id: actions
        spacing: Style.space(4)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        PanelActionButton {
          iconText: "󰏌"
          tooltipText: "Open folder"
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: !!(row.share && (row.share.mounted || row.share.mountPath))
          onClicked: root.openShare(row.share)
        }

        PanelActionButton {
          iconText: "󰏫"
          tooltipText: "Edit share"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.startEdit(row.share)
        }

        PanelActionButton {
          iconText: "󰆴"
          tooltipText: "Remove share"
          foreground: root.foreground
          hoverColor: root.urgent
          fontFamily: root.fontFamily
          onClicked: root.removeShare(row.share)
        }
      }

      Column {
        id: info
        spacing: Style.space(1)
        anchors.left: iconLabel.right
        anchors.leftMargin: Style.space(10)
        anchors.right: actions.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          width: parent.width
          text: row.share ? row.share.label : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: Model.shareSubtitle(row.share)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: row.statusText !== ""
          text: row.statusText
          color: row.statusColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }
}
