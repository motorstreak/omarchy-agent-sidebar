# Omarchy Agent Sidebar

Your Omarchy default coding agent (`omarchy default agent`) as a sidebar on one
key, with a searchable list of saved sessions when that agent is Claude Code.

It's an add-on to the [Sidebar plugin](https://github.com/motorstreak/omarchy-sidebar),
which it needs: the agent is one of your sidebars there (`Super + Tab` cycles
through it with the others, `Super + Alt + T` picks its theme), with a
remembered place of its own.

## Install

```bash
omarchy plugin add https://github.com/motorstreak/omarchy-sidebar.git --enable
omarchy plugin add https://github.com/motorstreak/omarchy-agent-sidebar.git --enable
```

Update with `omarchy plugin update agent-sidebar`; if an update changes a
`.qml` file, also run `omarchy restart shell`. Remove it with
`omarchy plugin remove agent-sidebar`; running agent windows stay, as ordinary
sidebars.

## Keys

| Key | Action |
|---|---|
| `Super + A` | Make the agent a sidebar and show it (launching it if needed); hide it if it's already showing |
| `Super + Shift + A` | Claude: the session list (below). Other agents: close the running one and start it fresh |
| `Super + Ctrl + Alt + A` | The agent sidebar back at its default size, against its edge at full height (forgets where you moved it; the edge stays) |

`Super + Shift + A` replaces Omarchy's ChatGPT key. In the sidebar, every key
of the Sidebar plugin works as in any other sidebar.

## The session list

`Super + Shift + A` lists the sessions the sidebar started, newest first (up
to 100), with **New session** always on top:

- Press `Enter` straight away for a new session named with the date and time.
- Type to search the sessions' names and prompts (every word, any order). The
  top row becomes **New session: _what you typed_**; pick it to start a session
  with that name. It's there even when nothing matches. While you type, the
  best match is highlighted, so `Enter` opens it; `Up` reaches New session.
- Pick a session to go back to it: a running one comes back as it was, one
  that isn't running is resumed.
- `Up`/`Down` (or `Tab`), `Page Up`/`Page Down` move; `Escape` clears the
  search, then closes; `Ctrl + U` clears the search, `Ctrl + Backspace`
  removes a word; a click picks a row, a click outside closes.

The session before a new one keeps running, hidden (closed only if it has no
message yet), and is in the list to come back to. Each running session is also
one of your sidebars for `Super + Tab`. Sessions show up once they have a
message, and in Claude's `/resume` picker too; renaming one with Claude's
`/rename` keeps it in the list.

## Claude Code

Omarchy's launcher can't pass Claude session options, so Claude is run
directly, pinned to one session: closing the sidebar and pressing `Super + A`
resumes the same conversation. It uses your normal Claude settings rather than
the auto permission mode Omarchy's launcher starts Claude in, and Claude's
"ANSI colours only" theme (light or dark by the sidebar's theme), so all of it
follows the colours the Sidebar plugin's `Super + Alt + T` gives it.

Other agents start through Omarchy's own launcher, exactly as
`Super + Shift + Ctrl + A` starts them. With no default agent set, `Super + A`
opens Omarchy's agent chooser.

### Handing off a new topic

Claude (or anything else) can leave a question waiting for a session of its
own:

```bash
echo "How do I set the MTU on wg0?" | ~/.config/omarchy/plugins/agent-sidebar/bin/agent-sidebar handoff "NordVPN MTU on wg0"
```

A menu asks straight away: `Enter` (**Start it now**) opens the new session
with the question already sent. **Later** (or `Escape`) leaves it waiting: for
the next hour, the session list offers **Start "NordVPN MTU on wg0" with your
question** under New session, highlighted, so `Super + Shift + A`, `Enter`
starts it. `handoff --no-ask NAME` skips the menu.

## Configure

Create `~/.config/omarchy/agent-sidebar.lua` returning the options to change,
then reload Hyprland (`hyprctl reload`). All options, with their defaults:

```lua
return {
  class = "sidebar.agent",          -- window class of the agent's terminal
  toggle = "SUPER + A",
  sessions = "SUPER + SHIFT + A",   -- false keeps Omarchy's ChatGPT key
  reset = "SUPER + CTRL + ALT + A",
  escape = true,                    -- Super + Escape hides it (false: the system menu)
  open_as = "sidebar",              -- or "tiled", "floating", "popped" (Super + O's), "docked" (Dock plugin)
}
```

`open_as` picks how the agent's windows open. Outside a sidebar, `Super + A`
goes to the agent's window (bringing up its workspace) and, pressed there,
back to the window you were in. With the Window Style plugin it's also on its
panel's All windows tab, as "Agent opens as", which saves it here.

Any key can be set to `false` to leave it unbound. Mistakes in the file are
shown as an "Agent Sidebar" notification. The look of the sidebar itself
(width, border, dim, drawer) is the Sidebar plugin's, in
`~/.config/omarchy/sidebar.lua`.

## Requirements

The Sidebar plugin 0.23.0 or later, and a default agent installed
(`omarchy default agent`). Like Omarchy's own agent launcher, it runs in
`~/Work` if that exists, otherwise in your home folder.

## How it works

Like the Sidebar plugin, its service loads `hypr/agent.lua` into the running
Hyprland with `hyprctl eval`, at start and after every config reload. It adds
the agent to the Sidebar plugin as a kind of sidebar (`SIDEBAR_KINDS`), opens
its windows floating on `special:sidebar` for the Sidebar plugin to take in,
and binds the keys. `bin/agent-sidebar` starts the agent and gathers the
session list, which `SessionPicker.qml` shows. State (the pinned Claude
session, the sessions started here) lives in
`$XDG_STATE_HOME/omarchy-agent-sidebar/` (normally `~/.local/state`); before
this plugin it was the Sidebar plugin's `omarchy-sidebar/agent`, which is moved
over on first run.
