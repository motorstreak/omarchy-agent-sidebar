-- Omarchy Agent Sidebar
--
-- Your Omarchy default coding agent (`omarchy default agent`) as a sidebar of
-- the Sidebar plugin, which it needs: this file adds the agent as a kind of
-- sidebar there (its own remembered place, theme and SUPER + ESCAPE) and binds
-- the agent's keys. With Claude Code it also keeps saved, searchable sessions
-- (see bin/agent-sidebar and SessionPicker.qml).
--
--   SUPER + A                the agent as the sidebar: shown, launched if
--                            needed; hidden if it's showing
--   SUPER + SHIFT + A        Claude: the session list, with "New session" on
--                            top (named by what you typed, or the date and
--                            time). Other agents: a fresh start
--   SUPER + CTRL + ALT + A   the agent sidebar back at its default size and
--                            place
--
-- Loaded into the running Hyprland by Service.qml with AGENT_SIDEBAR_DIR set to
-- the plugin folder. Options can be changed in
-- ~/.config/omarchy/agent-sidebar.lua (a Lua file returning a table like
-- `defaults`).

if AGENT_SIDEBAR_LOADED then
  return
end
if AGENT_SIDEBAR_DIR == nil then
  error("set AGENT_SIDEBAR_DIR to the plugin folder before loading agent.lua")
end
AGENT_SIDEBAR_LOADED = true

local dir = AGENT_SIDEBAR_DIR
local home = os.getenv("HOME")
local state_home = os.getenv("XDG_STATE_HOME")
if state_home == nil or state_home == "" then
  state_home = home .. "/.local/state"
end
local state_dir = state_home .. "/omarchy-agent-sidebar"
local quote = o.shell_quote

local function notify(message)
  hl.exec_cmd("notify-send -a 'Agent Sidebar' -- 'Agent Sidebar' " .. quote(message))
end

local reported = {}
local function guard(context, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      local message = context .. ": " .. tostring(err)
      if not reported[message] then
        reported[message] = true
        notify(message)
      end
    end
  end
end

-- Before 0.1.0 of this plugin, the Sidebar plugin kept the agent's state.
os.execute("old=" .. quote(state_home .. "/omarchy-sidebar/agent") .. "; new=" .. quote(state_dir) ..
  '; [ -d "$old" ] && [ ! -e "$new" ] && mv "$old" "$new"; mkdir -p "$new"')

-- Config -----------------------------------------------------------------------

local defaults = {
  class = "sidebar.agent", -- the agent terminal's window class
  toggle = "SUPER + A",
  sessions = "SUPER + SHIFT + A", -- replaces Omarchy's ChatGPT key
  reset = "SUPER + CTRL + ALT + A",
  escape = true, -- SUPER + ESCAPE hides it (instead of opening the system menu)
  -- How its windows open: "sidebar", "tiled", "floating", "popped" (floating
  -- and pinned, as Omarchy's SUPER + O) or "docked" (the Dock plugin's).
  -- Outside a sidebar, SUPER + A goes to it, and from it back.
  open_as = "sidebar",
}
local OPEN_AS = { sidebar = true, tiled = true, floating = true, popped = true, docked = true }

local config = {}
for k, v in pairs(defaults) do
  config[k] = v
end
do
  local problems = {}
  local chunk, load_err = loadfile(home .. "/.config/omarchy/agent-sidebar.lua")
  if chunk then
    local ok, overrides = pcall(chunk)
    if not ok then
      problems[#problems + 1] = tostring(overrides)
    elseif type(overrides) ~= "table" then
      problems[#problems + 1] = "the file must return a table"
    else
      for k, v in pairs(overrides) do
        if defaults[k] == nil then
          problems[#problems + 1] = "unknown option " .. tostring(k)
        elseif type(v) == type(defaults[k]) or (v == false and k ~= "class") then
          config[k] = v
        else
          problems[#problems + 1] = tostring(k) .. " must be a " .. type(defaults[k])
        end
      end
    end
  elseif load_err and not load_err:find("No such file", 1, true) then
    problems[#problems + 1] = load_err
  end
  -- Used as a terminal app id and in a window rule: keep it to a plain id.
  if not config.class:match("^[%w][%w._-]*$") then
    problems[#problems + 1] = "class must be letters, digits, '.', '_' or '-'"
    config.class = defaults.class
  end
  if not OPEN_AS[config.open_as] then
    problems[#problems + 1] = 'open_as must be "sidebar", "tiled", "floating", "popped" or "docked"'
    config.open_as = defaults.open_as
  end
  if #problems > 0 then
    notify("Problems in ~/.config/omarchy/agent-sidebar.lua: " .. table.concat(problems, "; "))
  end
end

local class = config.class

-- The agent as a kind of sidebar. SIDEBAR_KINDS is read by the Sidebar plugin
-- whenever it looks at a window, so this works whichever of the two loads first.
SIDEBAR_KINDS = SIDEBAR_KINDS or {}
SIDEBAR_KINDS.agent = { class = class, escape = config.escape }

local function is_agent(window)
  local c = window and window.class
  return c ~= nil and (c == class or c:sub(1, #class + 1) == class .. ".")
end

-- Where its windows open, by `open_as`. As a sidebar: floating on the first
-- sidebar workspace, and the Sidebar plugin takes it in from there. Otherwise
-- on the workspace showing, tiled (then popped out or docked, once open) or
-- floating. Matches the plain class and each Claude session's
-- "<class>.<session>", every regex metacharacter escaped. Named rules, made
-- again or turned off as the option changes.
local agent_match = { class = "^" .. class:gsub("[%^%$%(%)%.%[%]%*%+%-%?%{%}|\\]", "\\%0") .. "(\\..+)?$" }
local function open_rules()
  local function rule(name, on, spec)
    spec.name, spec.match = name, agent_match
    spec.enabled = on
    hl.window_rule(spec)
  end
  local mode = config.open_as
  rule("agent-sidebar-in-sidebar", mode == "sidebar", { float = true, workspace = "special:sidebar" })
  rule("agent-sidebar-tiled", mode == "tiled" or mode == "popped" or mode == "docked", { tile = true })
  rule("agent-sidebar-floating", mode == "floating", { float = true, center = true })
  -- For bin/agent-sidebar, which raises the sidebars' dim only for a sidebar.
  os.execute("mkdir -p " .. quote(state_dir))
  local f = io.open(state_dir .. "/open-as", "w")
  if f then
    f:write(mode, "\n")
    f:close()
  end
end
open_rules()

-- The agent's window ------------------------------------------------------------

local function read_line(path)
  local f = io.open(path, "r")
  if f == nil then
    return nil
  end
  local line = f:read("l")
  f:close()
  return line
end

-- The current session's window (bin/agent-sidebar keeps the earlier ones
-- running, hidden). A window with the plain class is another agent's, or a
-- Claude window from before the Sidebar plugin's 0.14.0: current unless
-- legacy-session says it runs another session.
local function agent_window()
  local session = read_line(state_dir .. "/session-id") or ""
  local legacy = read_line(state_dir .. "/legacy-session")
  local own = class .. ".s" .. session:sub(1, 8)
  local plain
  for _, w in ipairs(hl.get_windows()) do
    if session ~= "" and w.class == own then
      return w
    elseif w.class == class then
      plain = w
    end
  end
  if plain and (legacy == nil or legacy == session) then
    return plain
  end
end

-- The Sidebar plugin's API, or nil (with a note) when it isn't loaded.
local function sidebar_api()
  if type(sidebar) == "table" and sidebar.toggle_window then
    return sidebar
  end
  notify("Needs the Sidebar plugin (0.23.0 or later), enabled: omarchy plugin add https://github.com/motorstreak/omarchy-sidebar.git --enable")
end

local script = dir .. "/bin/agent-sidebar"
local function run(command)
  if config.open_as == "sidebar" then
    local api = sidebar_api()
    if api == nil then
      return
    end
    api.dim() -- the agent's window rule opens it into a sidebar
  elseif type(sidebar) == "table" and sidebar.hide then
    -- A window opens on the focused workspace: a sidebar's, while one shows,
    -- and the Sidebar plugin would take it in.
    sidebar.hide()
  end
  hl.exec_cmd("AGENT_SIDEBAR_CLASS=" .. quote(class) .. " " .. quote(script) .. " " .. command)
end

-- A second press while the agent is still starting would launch a second one
-- (on the same session, for Claude); the script also guards this.
local launched_at = 0
local function launch()
  if os.time() - launched_at >= 5 then
    launched_at = os.time()
    run("launch")
  end
end

-- Outside a sidebar --------------------------------------------------------------

-- The window focused before the agent's, to go back to.
local before_agent = nil
hl.on("window.active", guard("noting the focused window", function(window)
  if window and window.address and not is_agent(window) then
    before_agent = window.address
  end
end))

-- To the agent's window: onto the workspace showing if it's tucked away on a
-- special one (a sidebar, from before), then focused, which brings up its
-- workspace and monitor.
local function go_to(window)
  local ws = window.workspace and window.workspace.name or ""
  if ws:sub(1, 8) == "special:" then
    local m = hl.get_active_monitor()
    local regular = m and m.active_workspace
    if regular then
      hl.dispatch(hl.dsp.window.move({ window = "address:" .. window.address, workspace = regular.name, follow = false }))
    end
  end
  hl.dispatch(hl.dsp.focus({ window = "address:" .. window.address }))
end

-- A new window, once open: popped out or docked, as `open_as` says. Focused
-- first: both act on the focused window.
hl.on("window.open", guard("placing the agent's window", function(window)
  local mode = config.open_as
  if not is_agent(window) or (mode ~= "popped" and mode ~= "docked") then
    return
  end
  local address = window.address
  hl.timer(guard("placing the agent's window", function()
    hl.dispatch(hl.dsp.focus({ window = "address:" .. address }))
    hl.timer(guard("placing the agent's window", function()
      local active = hl.get_active_window()
      if active == nil or active.address ~= address then
        return
      end
      if mode == "popped" then
        hl.exec_cmd("omarchy-hyprland-window-pop")
      elseif type(dock) == "table" and dock.toggle then
        dock.toggle()
      else
        notify("open_as = \"docked\" needs the Dock plugin: https://github.com/motorstreak/omarchy-dock")
      end
    end), { timeout = 50, type = "oneshot" })
  end), { timeout = 150, type = "oneshot" })
end))

-- SUPER + A. Already showing: hide it. Anywhere else (hidden, on a workspace,
-- or another sidebar showing): it becomes the sidebar and shows. Not running:
-- launch it.
local function toggle()
  if config.open_as ~= "sidebar" then
    -- Outside a sidebar: to it, and from it back to the window before.
    local window = agent_window()
    local active = hl.get_active_window()
    if window == nil then
      launch()
    elseif active and active.address == window.address then
      if before_agent then
        hl.dispatch(hl.dsp.focus({ window = "address:" .. before_agent }))
      end
    else
      go_to(window)
    end
    return
  end
  local api = sidebar_api()
  local window = api and agent_window()
  if api == nil then
    return
  elseif window == nil then
    launch()
  else
    api.toggle_window(window.address)
  end
end

local function show()
  if config.open_as ~= "sidebar" then
    local window = agent_window()
    if window then
      go_to(window)
    end
    return window ~= nil
  end
  local api = sidebar_api()
  local window = api and agent_window()
  return window ~= nil and api.show_window(window.address)
end

local function reset()
  if config.open_as ~= "sidebar" then
    return toggle()
  end
  local api = sidebar_api()
  if api == nil then
    return
  end
  local window = agent_window()
  if window == nil then
    launch()
  else
    api.reset_window(window.address)
  end
end

-- Keys --------------------------------------------------------------------------

local function bind(keys, description, fn)
  if keys then
    hl.unbind(keys)
    o.bind(keys, description, guard(description, fn))
  end
end

bind(config.toggle, "Agent sidebar", toggle)
bind(config.sessions, "Agent sidebar sessions", function()
  run("sessions")
end)
bind(config.reset, "Reset agent sidebar", reset)

-- For bin/agent-sidebar and tests: `hyprctl eval 'agent_sidebar.show()'`.
-- `open_as`, from the Window Style plugin's panel: applied at once and saved to
-- ~/.config/omarchy/agent-sidebar.lua (its line replaced, or added).
local function set_open_as(mode)
  if not OPEN_AS[mode] then
    return
  end
  config.open_as = mode
  open_rules()
  local file = home .. "/.config/omarchy/agent-sidebar.lua"
  local f = io.open(file, "r")
  local text = f and f:read("a") or ""
  if f then
    f:close()
  end
  local line = '  open_as = "' .. mode .. '",'
  local new, n = text:gsub("\n[ \t]*open_as[ \t]*=[^\n]*", "\n" .. line, 1)
  if n == 0 then
    new, n = text:gsub("return%s*{", "return {\n" .. line, 1)
  end
  if n == 0 then
    new = "-- Agent Sidebar options (see the plugin's README).\nreturn {\n" .. line .. "\n}\n"
  end
  f = io.open(file, "w")
  if f then
    f:write(new)
    f:close()
  end
end

agent_sidebar = {
  toggle = toggle,
  show = show,
  reset = reset,
  set_open_as = set_open_as,
  open_as = function()
    return config.open_as
  end,
}
