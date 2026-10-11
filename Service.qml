import QtQuick
import Quickshell
import Quickshell.Io

// Omarchy shell plugins can't ship Hyprland config, so this service loads
// hypr/agent.lua into the running Hyprland with `hyprctl eval`: once at start
// and again after every config reload (which discards anything loaded at
// runtime). Failures are shown as an "Agent Sidebar" notification. (The same
// loader as the Sidebar plugin's.)
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null

  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")).replace(/\/$/, "")

  // A Lua long-bracket string that can hold any path: [==[ ... ]==] with
  // enough "=" that the path can't close it early.
  function luaString(value) {
    var level = ""
    while (value.indexOf("]" + level + "]") !== -1) level += "="
    return "[" + level + "[" + value + "]" + level + "]"
  }

  // Loads agent.lua unless this exact source is already loaded. Changed source
  // (a plugin update) can't be loaded over the old one, whose handlers stay
  // registered, so it reloads Hyprland, which brings it back here fresh.
  function load() {
    if (loader.running) {
      loader.pending = true
      return
    }
    loader.command = ["hyprctl", "eval",
      "AGENT_SIDEBAR_DIR = " + luaString(root.pluginDir) + "; " +
      "local f = io.open(AGENT_SIDEBAR_DIR .. '/hypr/agent.lua'); " +
      "local source = f and f:read('a'); if f then f:close() end; " +
      "if AGENT_SIDEBAR_LOADED and AGENT_SIDEBAR_SOURCE ~= source then AGENT_SIDEBAR_SOURCE = source; hl.exec_cmd('hyprctl reload'); return end; " +
      "AGENT_SIDEBAR_SOURCE = source; " +
      "local ok, err = pcall(dofile, AGENT_SIDEBAR_DIR .. '/hypr/agent.lua'); " +
      "if not ok then error(err, 0) end"]
    loader.running = true
  }

  function report(message) {
    console.warn("agent-sidebar: loading into Hyprland failed: " + message)
    Quickshell.execDetached(["notify-send", "-a", "Agent Sidebar", "--", "Agent Sidebar failed to load", message])
  }

  // Hyprland may not answer yet right at shell start; try a few more times
  // before reporting that.
  property int connectRetries: 0
  Timer {
    id: retry
    interval: 1000
    onTriggered: root.load()
  }

  Process {
    id: loader
    property bool pending: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var result = text.trim()
        if (result === "ok" || result === "") {
          root.connectRetries = 0
        } else if (result.indexOf("Couldn't connect") === 0 && root.connectRetries < 5) {
          root.connectRetries += 1
          retry.restart()
        } else {
          root.report(result)
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text.trim() !== "") root.report(text.trim())
      }
    }
    onExited: function() {
      if (pending) {
        pending = false
        root.load()
      }
    }
  }

  // Hyprland's events, on a connection of the plugin's own. The shell's (the
  // Hyprland module's) is made once and never again if Hyprland closes it
  // (quickshell #989); after that a reload left the plugin unloaded until the
  // shell restarted. This one is made afresh until it connects again. It loads
  // on connecting, in case a reload came while it was down.
  function eventsUp() {
    reconnect.stop()
    load()
  }

  function eventsDown() {
    reconnect.restart()
  }

  LazyLoader {
    id: events
    active: true

    Socket {
      path: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr/" + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") + "/.socket2.sock"
      connected: true
      onConnectionStateChanged: connected ? root.eventsUp() : root.eventsDown()
      // A socket that connects at once does so before the handler above is
      // attached, and one that fails never changes state: so check.
      Component.onCompleted: Qt.callLater(function() { connected ? root.eventsUp() : root.eventsDown() })
      parser: SplitParser {
        onRead: function(line) {
          if (line.split(">>")[0] === "configreloaded") root.load()
        }
      }
    }
  }

  // A fresh socket each try: setting `connected` again after a failed try
  // doesn't try again.
  Timer {
    id: reconnect
    interval: 2000
    onTriggered: {
      events.active = false
      events.active = true
    }
  }

  Component.onCompleted: load()

  SessionPicker {}

  // The shell destroys services on every plugin rescan and restart, not only
  // when this plugin is disabled. So wait, and unload only if it really is
  // disabled or removed: reload Hyprland to drop the keys and window rule (the
  // agent's windows stay, as ordinary sidebars).
  // The shell answers plugin queries only once it is up again, so keep asking
  // for a while; without a clear "not enabled" answer, leave everything as is.
  Component.onDestruction: Quickshell.execDetached(["bash", "-c",
    "sleep 3; " +
    "for i in $(seq 30); do out=$(omarchy plugin list --json 2>/dev/null) && [ -n \"$out\" ] && break; out=; sleep 1; done; " +
    "[ -n \"$out\" ] || exit 0; " +
    "jq -e 'type == \"array\"' >/dev/null <<<\"$out\" || exit 0; " +
    "jq -e '.[] | select(.id == \"agent-sidebar\" and .enabled)' >/dev/null <<<\"$out\" && exit 0; " +
    "hyprctl reload >/dev/null"])
}
