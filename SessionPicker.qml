import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The Claude session list (SUPER + SHIFT + A), in the look of Omarchy's menus.
// bin/agent-sidebar sends the sessions; typing searches their names and
// prompts. "New session" stays on top whatever the search: picked with an
// empty search it's named with the date and time, otherwise with what was
// typed. A question handed off from another session waits under it. Picking
// runs bin/agent-sidebar again (new, new --handoff, open).
Scope {
  id: root

  property bool open: false
  property string agentClass: ""
  property string script: ""
  property string monitor: ""
  property string handoff: "" // a waiting question's session name
  property var sessions: [] // [{ id, title, detail, current, time }], newest first
  property string filter: ""
  property int index: 0
  property string stamp: "" // the date and time a new session is named with

  readonly property string name: filter.trim().replace(/\s+/g, " ").slice(0, 80)

  // Every word of the search, in any order, in the name or the prompts.
  function matching(search) {
    var words = search.toLowerCase().split(/\s+/).filter(function(w) { return w !== "" })
    return sessions.filter(function(s) {
      var text = (s.title + " " + s.detail).toLowerCase()
      return words.every(function(w) { return text.indexOf(w) >= 0 })
    })
  }
  readonly property var matches: matching(filter)
  readonly property bool handoffShown: handoff !== "" && (filter === ""
    || handoff.toLowerCase().indexOf(filter.toLowerCase().trim()) >= 0)
  // The rows always on top: "New session", then any handed-off question.
  readonly property int pinned: handoffShown ? 2 : 1
  readonly property int count: pinned + matches.length

  function show(payload) {
    var p = JSON.parse(payload)
    agentClass = String(p.class || "")
    script = String(p.script || "")
    monitor = String(p.monitor || "")
    handoff = String(p.handoff || "")
    sessions = Array.isArray(p.sessions) ? p.sessions : []
    stamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm")
    filter = ""
    index = handoff !== "" ? 1 : 0
    open = true
    keys.forceActiveFocus()
  }

  // Typing: the best match, or "New session" when nothing matches. Cleared:
  // "New session" (or the waiting question), as the key always started one.
  // (Worked out afresh: the bindings above may not have caught up yet.)
  onFilterChanged: {
    var handoffToo = handoff !== "" && (filter === "" || handoff.toLowerCase().indexOf(filter.toLowerCase().trim()) >= 0)
    index = filter === "" ? (handoffToo ? 1 : 0) : (matching(filter).length > 0 ? (handoffToo ? 2 : 1) : 0)
  }

  function move(step) {
    index = Math.max(0, Math.min(count - 1, index + step))
  }

  function run(args) {
    Quickshell.execDetached(["env", "AGENT_SIDEBAR_CLASS=" + agentClass, script].concat(args))
  }

  function commit() {
    if (!open) return
    open = false
    if (index === 0) {
      run(name === "" ? ["new"] : ["new", "--", name])
    } else if (index === 1 && handoffShown) {
      run(["new", "--handoff"])
    } else {
      var s = matches[index - pinned]
      if (s) run(["open", s.id, s.title])
    }
  }

  function cancel() {
    open = false
  }

  IpcHandler {
    target: "agent-sidebar-sessions"
    function open(payload: string): string { root.show(payload); return "ok" }
    function state(): string { return (root.open ? "open " : "closed ") + root.index + " " + root.count + " " + root.filter }
    // For tests: type, press Enter, or close.
    function type(text: string): string { root.filter = text; return "ok" }
    function pick(): string { root.commit(); return "ok" }
    function close(): string { root.cancel(); return "ok" }
    function rows(): string {
      var out = [root.name === "" ? "New session" : "New session: " + root.name]
      if (root.handoffShown) out.push("handoff: " + root.handoff)
      return out.concat(root.matches.map(function(s) { return s.title })).join("\n")
    }
  }

  PanelWindow {
    id: panel

    screen: {
      var screens = Quickshell.screens
      for (var i = 0; i < screens.length; i++) {
        if (screens[i].name === root.monitor) return screens[i]
      }
      return screens.length > 0 ? screens[0] : null
    }
    visible: root.open
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-agent-sidebar-sessions"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    readonly property int rowHeight: Math.max(Style.space(58), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
    readonly property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
    readonly property int padding: Style.spacing.panelPadding
    readonly property int spacing: Style.spacing.md
    readonly property int maxHeight: Math.min(Style.space(640), height - Style.gapsOut * 2)
    readonly property int chrome: padding * 2 + headerHeight + spacing
    readonly property int fullHeight: Math.min(maxHeight, chrome + root.count * rowHeight)

    Rectangle {
      anchors.fill: parent
      color: Commons.Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.cancel()
    }

    BorderSurface {
      id: card

      width: Math.min(Style.space(620), panel.width - Style.gapsOut * 2)
      height: panel.fullHeight
      anchors.horizontalCenter: parent.horizontalCenter
      // Where a full card's top would be, whatever its height, so the search
      // line stays put as the list shrinks.
      y: Math.max(Style.gapsOut, Math.round((panel.height - panel.maxHeight) / 2))
      radius: Style.cornerRadius
      // Nearly solid: Omarchy's menus are see-through (the theme's
      // menu.background-alpha), which made the text behind hard to tell apart
      // from the sessions' prompts.
      // As Omarchy's menus: their background, border and its width from
      // shell.toml's [menu] (the Window Style plugin's Menus tab).
      color: Commons.Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.space(2)))

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keys
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filter) root.filter = ""
            else root.cancel()
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.commit()
          } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
            root.move(-1)
          } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
            root.move(1)
          } else if (event.key === Qt.Key_PageUp) {
            root.move(-8)
          } else if (event.key === Qt.Key_PageDown) {
            root.move(8)
          } else if (event.key === Qt.Key_Backspace) {
            root.filter = (event.modifiers & Qt.ControlModifier) ? root.filter.replace(/\S*\s*$/, "") : root.filter.slice(0, -1)
          } else if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
            root.filter = ""
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
              && event.text.charCodeAt(0) !== 127
              && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.filter += event.text
          } else {
            return
          }
          event.accepted = true
        }
      }

      Column {
        anchors.fill: parent
        anchors.margins: panel.padding
        spacing: panel.spacing

        Text {
          width: parent.width
          height: panel.headerHeight
          verticalAlignment: Text.AlignVCenter
          textFormat: Text.PlainText
          text: root.filter || "Claude sessions…"
          color: Commons.Color.menu.text
          opacity: root.filter ? 1 : 0.58
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.heading
          elide: Text.ElideLeft
        }

        Column {
          width: parent.width

          SessionRow {
            rowIndex: 0
            icon: "󰐕"
            label: root.name === "" ? "New session" : "New session: " + root.name
            detail: root.name === "" ? "Named " + root.stamp + "; type to name it" : "Starts a session with this name"
          }

          SessionRow {
            visible: root.handoffShown
            rowIndex: 1
            icon: "󰁔"
            label: "Start \"" + root.handoff + "\" with your question"
            detail: "A question handed off from another session"
          }

          ListView {
            id: list
            width: parent.width
            height: card.height - panel.chrome - root.pinned * panel.rowHeight
            clip: true
            model: root.matches
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: root.index - root.pinned
            highlightMoveDuration: 0
            onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: SessionRow {
              required property var modelData
              required property int index
              width: ListView.view.width
              rowIndex: index + root.pinned
              icon: "󰍩"
              label: modelData.title
              detail: modelData.detail
              when: (modelData.current ? "current · " : "") + root.ago(modelData.time)
            }
          }
        }
      }
    }
  }

  // When a session last changed, as "5 min ago", "yesterday", "3 weeks ago".
  function ago(seconds) {
    if (!seconds) return ""
    var then = new Date(seconds * 1000), now = new Date()
    var s = Math.max(0, (now - then) / 1000)
    if (s < 60) return "just now"
    if (s < 3600) return Math.floor(s / 60) + " min ago"
    var days = Math.round((new Date(now.getFullYear(), now.getMonth(), now.getDate())
      - new Date(then.getFullYear(), then.getMonth(), then.getDate())) / 86400000)
    if (days === 0) { var h = Math.floor(s / 3600); return h + (h === 1 ? " hour ago" : " hours ago") }
    if (days === 1) return "yesterday"
    if (days < 7) return days + " days ago"
    if (days < 31) { var w = Math.floor(days / 7); return w + (w === 1 ? " week ago" : " weeks ago") }
    if (days < 365) { var m = Math.floor(days / 30); return m + (m === 1 ? " month ago" : " months ago") }
    var y = Math.floor(days / 365); return y + (y === 1 ? " year ago" : " years ago")
  }

  component SessionRow: Rectangle {
    id: row

    property int rowIndex: 0
    property string icon: ""
    property string label: ""
    property string detail: ""
    property string trailing: ""
    // At the right of the title line.
    property string when: ""
    readonly property bool current: rowIndex === root.index

    width: parent ? parent.width : 0
    height: visible ? panel.rowHeight : 0
    radius: Style.cornerRadius
    color: current ? Commons.Color.menu.selectedBackground : "transparent"

    Text {
      id: glyph
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(36)
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: row.icon
      color: row.current ? Commons.Color.menu.selectedText : Commons.Color.menu.text
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.iconLarge
    }

    Column {
      anchors.left: glyph.right
      anchors.leftMargin: Style.space(6)
      anchors.right: tail.left
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)

      Item {
        width: parent.width
        height: titleText.implicitHeight

        Text {
          id: titleText
          anchors.left: parent.left
          anchors.right: whenText.left
          anchors.rightMargin: whenText.text !== "" ? Style.space(10) : 0
          textFormat: Text.PlainText
          text: row.label
          color: row.current ? Commons.Color.menu.selectedText : Commons.Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.heading
          font.weight: Font.Medium
          elide: Text.ElideRight
        }

        Text {
          id: whenText
          anchors.right: parent.right
          anchors.baseline: titleText.baseline
          textFormat: Text.PlainText
          text: row.when
          color: row.current ? Commons.Color.menu.selectedText : Commons.Color.menu.text
          opacity: 0.58
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      Text {
        width: parent.width
        visible: text !== ""
        textFormat: Text.PlainText
        text: row.detail
        color: row.current ? Commons.Color.menu.selectedText : Commons.Color.menu.text
        opacity: 0.52
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }

    Text {
      id: tail
      anchors.right: parent.right
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: row.trailing
      color: row.current ? Commons.Color.menu.selectedText : Commons.Color.menu.text
      opacity: 0.58
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.bodySmall
    }

    MouseArea {
      anchors.fill: parent
      onClicked: {
        root.index = row.rowIndex
        root.commit()
      }
    }
  }
}
