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
}

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
  if #problems > 0 then
    notify("Problems in ~/.config/omarchy/agent-sidebar.lua: " .. table.concat(problems, "; "))
  end
end

local class = config.class

-- The agent as a kind of sidebar. SIDEBAR_KINDS is read by the Sidebar plugin
-- whenever it looks at a window, so this works whichever of the two loads first.
SIDEBAR_KINDS = SIDEBAR_KINDS or {}
SIDEBAR_KINDS.agent = { class = class, escape = config.escape }

-- Opens floating on the first sidebar workspace; the Sidebar plugin takes it in
-- from there. Matches the plain class and each Claude session's
-- "<class>.<session>", every regex metacharacter escaped.
hl.window_rule({
  match = { class = "^" .. class:gsub("[%^%$%(%)%.%[%]%*%+%-%?%{%}|\\]", "\\%0") .. "(\\..+)?$" },
  float = true,
  workspace = "special:sidebar",
})

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
  local own = class .. "." .. session:sub(1, 8)
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
  local api = sidebar_api()
  if api == nil then
    return
  end
  api.dim() -- the agent's window rule opens it into a sidebar
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

-- SUPER + A. Already showing: hide it. Anywhere else (hidden, on a workspace,
-- or another sidebar showing): it becomes the sidebar and shows. Not running:
-- launch it.
local function toggle()
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
  local api = sidebar_api()
  local window = api and agent_window()
  return window ~= nil and api.show_window(window.address)
end

local function reset()
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
agent_sidebar = {
  toggle = toggle,
  show = show,
  reset = reset,
}
