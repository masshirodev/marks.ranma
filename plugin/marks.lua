-- marks: the shell's prompts as places in a pane. Jump from one to the next,
-- copy a command's output without copy mode, and list the commands still in
-- the scrollback.
--
-- It reads pane:marks(), so the shell has to mark its prompts and commands
-- with OSC 133: the README's "Shell integration" has zsh, bash and
-- powerlevel10k. A pane with no marks says why in a toast (and on the list's
-- status), its shell sending none or drawing its prompt over them, and
-- nothing else happens.
--
-- leader ' is a folder (+marks), ' being vim's key for marks:
--   ' k    the previous prompt, scrolled to the top of the view; then MARKS
--   ' j    the next prompt (past the newest, the bottom); then MARKS, even
--          when there was nowhere to go
--   ' y    copy the output of the last command that finished
--   ' c    copy that command's command line
--   ' l    the list: the commands in the scrollback, newest first, with their
--          exit status, how long they ran (when ranma saw them finish) and the
--          end of their output. On it:
--            enter  jump to it (then MARKS)    y  copy its output
--            c      copy its command line      r  read the pane again
-- MARKS is a mode (the bar says MARKS; esc or enter leaves it):
--   k j ↑ ↓  the previous / next prompt      g G  the oldest / the bottom
--   y        copy the output of the command at the prompt jumped to
--   c        copy its command line           v    copy mode at that prompt
--   l        the list
-- :marks [list|prev|next|copy|copy-command] in the palette does the same,
-- and so does ranma.emit("marks", "prev") from a bind of your own.
--
-- ' k and ' j start from the bottom of the pane. MARKS mode, the palette and
-- the event go on from the prompt last jumped to, until a command starts in
-- that pane (ranma cannot tell a plugin how far a pane is scrolled).
-- From the bottom, the previous prompt is the newest one above the screen.
--
-- A command is a prompt whose command ran; an Enter on an empty line is not
-- one. Its output is its lines from where it started printing to the next
-- prompt, blank rows at the end left out; a row as wide as the pane is taken
-- as wrapped and joined to the next. The command line is read off the screen
-- and the prompt cut from it: up to the first `$ `, `% `, `# `, `> `, `❯ `,
-- `➜ `, `» ` or `λ ` on its first line that has one, or what marks.prompt
-- matches. How long a command ran comes from the command_finished hook, kept
-- for each pane until the configuration reloads, and is shown only where the
-- exit statuses line up, newest first; a command that finished before a
-- reload shows none. A shell whose marks lose their exit status (p10k's)
-- shows · for it, and no durations.
-- Options (settings panel, "marks" group): marks.prompt, marks.max,
-- marks.preview.
--
-- Needs a ranma with pane:marks(): the first release after 0.2.0.
-- ranma's plugin API: https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md ("Pane
-- handles", "Screens", "Modes", "Hooks").

ranma.option("marks.prompt", {
  type = "string", default = "",
  name = "Prompt", desc = "A Lua pattern matching the prompt before a command line, e.g. \"^.-%$ \". Empty: up to the first $, %, #, >, ❯, ➜, » or λ and a space.",
})
ranma.option("marks.max", {
  type = "int", min = 10, max = 1000, step = 10, default = 200, slider = false,
  name = "Most commands", desc = "The most commands the list shows, newest first.",
})
ranma.option("marks.preview", {
  type = "int", min = 0, max = 20, default = 8,
  name = "Output lines", desc = "The last lines of output the list shows under the selected command.",
})

local ENDS = { "$ ", "% ", "# ", "> ", "❯ ", "➜ ", "» ", "λ " }
-- A command line longer than this many rows is not read whole.
local MAX_ROWS = 50
local RUNS = 1000

-- Why a pane has no marks. Commands seen to finish there (the hook hears
-- the shell's marks as they pass) mean the shell sends them and its prompt
-- is drawn over them: p10k's transient prompt does, with the zsh lines.
local function why_none(p)
  if p.vars.marks_runs and #p.vars.marks_runs > 0 then
    return "pane " .. p.id .. "'s prompt is drawn over its marks (p10k does that):"
      .. " see marks.ranma's README."
  end
  return "pane " .. p.id .. "'s shell sends no prompt marks: see command_finished in"
    .. " ranma's CONFIG.md."
end

local function no_marks(p)
  ranma.toast("marks: " .. why_none(p), { urgent = true })
end

-- Line numbers as the history plugin writes them: a true minus for the scrollback.
local function num(n)
  return n < 0 and ("−" .. -n) or tostring(n)
end

local function plural(n, word)
  return n .. " " .. word .. (n == 1 and "" or "s")
end

local function duration(d)
  if not d then return nil end
  if d < 10 then return ("%.1fs"):format(d) end
  if d < 60 then return ("%ds"):format(math.floor(d + 0.5)) end
  if d < 3600 then return ("%dm%02ds"):format(d // 60, math.floor(d % 60)) end
  return ("%dh%02dm"):format(d // 3600, math.floor(d % 3600 / 60))
end

-- What follows the prompt on a line, or nil when the line shows no prompt.
-- Lines come trimmed, so a prompt with nothing after it has lost the space
-- it ends with: one is put back.
local function after_prompt(text)
  text = text .. " "
  local pattern = ranma.get("marks.prompt")
  if pattern ~= "" then
    local ok, _, e = pcall(string.find, text, pattern)
    if ok and e then return (text:sub(e + 1):gsub("%s+$", "")) end
    return nil
  end
  local first
  for _, t in ipairs(ENDS) do
    local s, e = text:find(t, 1, true)
    if s and (not first or s < first[1]) then first = { s, e } end
  end
  return first and (text:sub(first[2] + 1):gsub("%s+$", ""))
end

-- Rows as lines: :lines() gives screen rows, and a row as wide as the pane
-- ran on into the next one (a guess: a line that fills the width exactly is
-- joined too).
local function unwrap(p, rows)
  local out, cur = {}, nil
  for _, r in ipairs(rows) do
    cur = (cur or "") .. r
    if (utf8.len(r) or #r) < p.cols then
      out[#out + 1] = cur
      cur = nil
    end
  end
  if cur then out[#out + 1] = cur end
  return out
end

-- The command line of a mark, read off the screen, prompt cut: "" for an
-- Enter on an empty line. Kept on the mark, which is read once per call.
local function command_of(p, m)
  if m.cmd then return m.cmd end
  local stop = m.output or m.finished
  if not stop then return "" end
  -- A B can land past the command line (p10k's transient prompt redraws the
  -- prompt and not the text after it): then the prompt's line is the start.
  local first = m.command < stop and m.command or m.prompt
  local last = math.min(math.max(first, stop - 1), first + MAX_ROWS)
  local lines = unwrap(p, p:lines(first, last))
  local prompt_seen = false
  for i, l in ipairs(lines) do
    local cmd = after_prompt(l)
    if cmd then prompt_seen = true end
    if cmd and cmd:find("%S") then
      local out = { cmd }
      -- Lines after the first carry the shell's PS2 (`> `, zsh's `quote> `).
      for j = i + 1, #lines do out[#out + 1] = (lines[j]:gsub("^[%w ]*> ", "", 1)) end
      m.cmd = table.concat(out, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
      return m.cmd
    end
  end
  -- No prompt seen: the line written last before the output.
  m.cmd = prompt_seen and "" or ((lines[#lines] or ""):gsub("^%s+", ""))
  return m.cmd
end

-- A command line as one short line, for the bar and a row.
local function short(cmd, width)
  local first = cmd:match("^[^\n]*")
  if first ~= cmd then first = first .. " …" end
  if first == "" then first = "(empty)" end
  width = width or 40
  if utf8.len(first) and utf8.len(first) > width then
    first = first:sub(1, utf8.offset(first, width) - 1) .. "…"
  end
  return first
end

-- The output of a mark that ran, as lines; for a command still running, what
-- it printed so far.
local function output_lines(p, m)
  if not m.output then return {} end
  local _, bottom = p:range()
  local last = m.finished and (m.finished - 1) or bottom
  if last < m.output then return {} end
  local lines = unwrap(p, p:lines(m.output, last))
  while #lines > 0 and not lines[#lines]:find("%S") do lines[#lines] = nil end
  return lines
end

-- The commands that ran (or run) in the pane, oldest first, and every mark.
-- A command has its output mark (C), or finished with a command line: zsh's
-- PROMPT_SP overwrites the cell the C of a command that printed nothing
-- waits on, so that C is lost. An Enter on an empty line is no command, nor
-- is a prompt finished on its own line (zsh prints a PS1 holding the marks
-- twice, which leaves an empty one before each).
local function read(p)
  local ok, ms = pcall(function() return p:marks() end)
  -- A ranma from before pane:marks() (0.2.0 and older) loads the plugin fine.
  if not ok then error("marks: this ranma (" .. ranma.version .. ") has no pane:marks();"
    .. " the release after 0.2.0 does", 0) end
  local ran = {}
  for i, m in ipairs(ms) do
    -- A prompt redrawn (a resize, p10k refreshing) loses the D sent before
    -- it, but the next prompt says the command is over: its status unknown.
    if not m.finished and ms[i + 1] then m.finished = ms[i + 1].prompt end
    if m.output or (m.finished and m.finished > m.prompt and command_of(p, m) ~= "") then
      ran[#ran + 1] = m
    end
  end
  return ran, ms
end

-- How long each finished command ran, by index into `ran`: the hook's
-- records matched to the marks newest first, as far as the exit statuses
-- agree. The first disagreement ends it, so a duration is never another
-- command's.
local function durations(p, ran)
  local runs, out = p.vars.marks_runs or {}, {}
  local r = #runs
  for j = #ran, 1, -1 do
    local m = ran[j]
    if m.finished then
      local rec = runs[r]
      if not rec or rec.exit ~= m.exit then break end
      out[j], r = rec.duration, r - 1
    end
  end
  return out
end

ranma.on("command_finished", function(ev)
  local p = ranma.pane(ev.pane)
  if not p then return end
  local runs = p.vars.marks_runs or {}
  runs[#runs + 1] = { exit = ev.exit, duration = ev.duration }
  if #runs > RUNS then table.remove(runs, 1) end
  p.vars.marks_runs = runs
end)

-- The prompt last jumped to: its pane and how many commands are newer. That
-- count holds while lines scroll and old ones drop off the top, until a new
-- command starts in the pane, which is also when the view goes back down.
local cursor = nil

ranma.on("command_started", function(ev)
  if cursor and cursor.pane == ev.pane then cursor = nil end
end)

local function at(p, ran)
  if not cursor or cursor.pane ~= p.id then return nil end
  local i = #ran - cursor.newer
  if i >= 1 and i <= #ran then return i end
  cursor = nil
end

-- Scroll so a line is at the top of the view. pane:scroll_to puts a
-- scrollback line mid-view, so the line half a screen below it is asked for;
-- a line on the screen is shown from the bottom, and one within half a
-- screen above it lands as high as scrolling allows.
local function jump(p, line)
  if line >= 0 then return p:scroll_to(0) end
  p:scroll_to(math.min(line + p.rows // 2, -1))
end

local function go(p, ran, i)
  cursor = { pane = p.id, newer = #ran - i }
  jump(p, ran[i].prompt)
  local m = ran[i]
  local how = m.finished and (m.exit and ("exit " .. m.exit) or "") or "running"
  ranma.notify(("marks: %d/%d  %s  %s"):format(i, #ran, short(command_of(p, m)), how))
end

-- The pane and its commands, or nil after saying why there are none.
local function commands()
  local p = ranma.pane()
  if not p then
    ranma.notify("marks: no pane")
    return nil
  end
  local ran, ms = read(p)
  if #ms == 0 then
    no_marks(p)
    return nil
  end
  if #ran == 0 then
    ranma.notify("marks: no commands in pane " .. p.id .. "'s scrollback")
    return nil
  end
  return p, ran
end

-- One prompt back (-1) or on (1). `fresh` starts from the bottom of the pane
-- instead of the prompt last jumped to. True if it moved, false if there was
-- nowhere to go, nil if the pane has no commands.
local function step(dir, fresh)
  local p, ran = commands()
  if not p then return nil end
  local i = not fresh and at(p, ran) or nil
  local target
  if i then
    target = i + dir
  elseif dir < 0 then
    for j = #ran, 1, -1 do
      if ran[j].prompt < 0 then target = j break end
    end
    if not target then
      ranma.notify("marks: every prompt is on the screen")
      return false
    end
  else
    p:scroll_to(0)
    ranma.notify("marks: at the bottom")
    return false
  end
  if target < 1 then
    ranma.notify("marks: at the oldest prompt in the scrollback")
    return true
  end
  if target > #ran then
    cursor = nil
    p:scroll_to(0)
    ranma.notify("marks: at the bottom")
    return true
  end
  go(p, ran, target)
  return true
end

local function oldest()
  local p, ran = commands()
  if p then go(p, ran, 1) end
end

local function bottom()
  local p = ranma.pane()
  if not p then return end
  cursor = nil
  p:scroll_to(0)
end

-- The command to copy: at the prompt last jumped to, or (fresh, or with
-- none) the last one that finished.
local function chosen(fresh)
  local p, ran = commands()
  if not p then return nil end
  local i = not fresh and at(p, ran) or nil
  if not i then
    for j = #ran, 1, -1 do
      if ran[j].finished then i = j break end
    end
  end
  if not i then
    ranma.notify("marks: no command has finished in pane " .. p.id)
    return nil
  end
  return p, ran[i]
end

local function copy_output(p, m)
  local lines = output_lines(p, m)
  local what = short(command_of(p, m))
  if #lines == 0 then return ranma.notify("marks: " .. what .. " printed nothing") end
  ranma.copy(table.concat(lines, "\n"))
  ranma.notify("marks: copied " .. plural(#lines, "line") .. " of " .. what)
end

local function copy_command(p, m)
  local cmd = command_of(p, m)
  if cmd == "" then return ranma.notify("marks: no command line to copy") end
  ranma.copy(cmd)
  ranma.notify("marks: copied " .. short(cmd))
end

local function copy_last(fresh)
  local p, m = chosen(fresh)
  if p then copy_output(p, m) end
end

local function copy_last_command(fresh)
  local p, m = chosen(fresh)
  if p then copy_command(p, m) end
end

local function copy_mode_here()
  local p, ran = commands()
  if not p then return end
  local i = at(p, ran)
  local m = i and ran[i] or ran[#ran]
  p:copy_mode(m.prompt, 0)
end

-- The list.

local state = { screen = nil, pane = nil }
local list

local function close()
  if state.screen then state.screen:close() end
  state.screen = nil
end

-- A row's command, read again: the row's id is how many commands are newer,
-- which holds while the list is open unless a command starts in the pane.
local function row_command(id)
  local p = state.pane
  if not (p and p:alive()) then
    ranma.notify("marks: the pane is gone")
    return nil
  end
  local ran = read(p)
  local i = #ran - tonumber(id)
  if not ran[i] then
    ranma.notify("marks: that command is gone from the scrollback")
    return nil
  end
  return p, ran, i
end

local function status_of(m)
  if not m.finished then return { "…", "accent" }, { "running", "accent" } end
  if m.exit == nil then return { "·", "dim" }, nil end
  if m.exit == 0 then return { "✓", "dim" }, { "exit 0", "dim" } end
  return { "✗", "urgent" }, { "exit " .. m.exit, "urgent" }
end

local function body(p)
  local ran, ms = read(p)
  if #ms == 0 then return nil, 0, 0 end
  local took = durations(p, ran)
  local max, preview = ranma.get("marks.max"), ranma.get("marks.preview")
  local rows, failed = {}, 0
  for j = #ran, math.max(1, #ran - max + 1), -1 do
    local m = ran[j]
    local cmd = command_of(p, m)
    local out = output_lines(p, m)
    local mark, exit = status_of(m)
    if m.finished and m.exit and m.exit ~= 0 then failed = failed + 1 end
    local value = {}
    if took[j] then value[#value + 1] = duration(took[j]) end
    -- The mark says it went well; only a failure, or a run, takes words.
    if exit and m.exit ~= 0 then value[#value + 1] = exit[1] end
    local log = {}
    for k = math.max(1, #out - preview + 1), #out do log[#log + 1] = out[k] end
    local facts = { "facts", { "prompt", num(m.prompt) }, { "output", plural(#out, "line") } }
    if exit then facts[#facts + 1] = { "", exit[1], role = exit[2] } end
    if took[j] then facts[#facts + 1] = { "took", duration(took[j]) } end
    local detail = {}
    if preview > 0 then
      detail[1] = #log > 0 and { "log", lines = log, n = preview }
        or { "text", "no output", role = "dim" }
    end
    detail[#detail + 1] = facts
    if cmd:find("\n") then table.insert(detail, 1, { "text", cmd, max = 3 }) end
    rows[#rows + 1] = {
      "row", id = tostring(#ran - j), name = short(cmd, 200), mark = mark,
      note = num(m.prompt),
      value = #value > 0 and { table.concat(value, " · "), exit and m.exit ~= 0 and exit[2] or "dim" } or nil,
      keys = {
        { "enter", "jump", function(id)
          local q, r, i = row_command(id)
          if not q then return end
          close()
          q:focus()
          go(q, r, i)
          ranma.action("mode marks")
        end },
        { "y", "copy output", function(id)
          local q, r, i = row_command(id)
          if q then copy_output(q, r[i]) end
        end },
        { "c", "copy command", function(id)
          local q, r, i = row_command(id)
          if q then copy_command(q, r[i]) end
        end },
      },
      detail = detail,
    }
  end
  return rows, #ran, failed
end

local function view(p)
  local rows, n, failed = body(p)
  local fields = {}
  if not rows then
    fields.body = { { "text", why_none(p) .. " Then run a command.", role = "dim" } }
    fields.status = { "no prompt marks", "urgent" }
    fields.count = false
  else
    fields.body = rows
    fields.count = plural(n, "command")
    fields.status = failed > 0 and { "pane " .. p.id .. " · " .. failed .. " failed", "urgent" }
      or { "pane " .. p.id, "dim" }
  end
  return fields
end

list = function()
  local p = ranma.pane()
  if not p then return ranma.notify("marks: no pane") end
  state.pane = p
  local fields = view(p)
  state.screen = ranma.screen {
    title = "marks", filter = "names", options = true,
    detail = math.max(3, ranma.get("marks.preview") + 2),
    body = fields.body, count = fields.count or nil, status = fields.status,
    empty = "no commands in the scrollback",
    keys = {
      { "r", "read again", function()
        if state.screen and state.pane:alive() then state.screen:set(view(state.pane)) end
      end },
    },
    card = {
      { "enter", "jump to its prompt, then MARKS mode" },
      { "y", "copy its output" },
      { "c", "copy its command line" },
      { "r", "read the pane again" },
    },
    on_close = function() state.screen = nil end,
  }
end

-- Binds: a folder on ' (vim's marks key), and MARKS for walking on.

local function walk(dir)
  return function()
    -- MARKS even when this step had nowhere to go (at the bottom, j): the
    -- next key may. Not for a pane with no commands.
    if step(dir, true) ~= nil then ranma.action("mode marks") end
  end
end

ranma.bind("'", { folder = "marks", group = "plugins" })
ranma.bind("' k", walk(-1), { desc = "previous prompt", exit = false })
ranma.bind("' j", walk(1), { desc = "next prompt", exit = false })
ranma.bind("' y", function() copy_last(true) end, { desc = "copy output", exit = true })
ranma.bind("' c", function() copy_last_command(true) end, { desc = "copy command", exit = true })
ranma.bind("' l", function() list() end, { desc = "list", exit = true })

ranma.mode("marks", {
  label = "MARKS",
  binds = {
    k = { function() step(-1) end, desc = "previous prompt" },
    up = { function() step(-1) end, desc = "previous prompt" },
    j = { function() step(1) end, desc = "next prompt" },
    down = { function() step(1) end, desc = "next prompt" },
    g = { oldest, desc = "oldest prompt" },
    ["shift+g"] = { bottom, desc = "bottom" },
    y = { function() copy_last(false) end, desc = "copy output" },
    c = { function() copy_last_command(false) end, desc = "copy command" },
    v = { copy_mode_here, desc = "copy mode", exit = true },
    l = { function() list() end, desc = "list", exit = true },
  },
})

local function run(what)
  what = tostring(what or ""):match("^%s*(.-)%s*$")
  if what == "" or what == "list" then list()
  elseif what == "prev" then step(-1)
  elseif what == "next" then step(1)
  elseif what == "copy" then copy_last(false)
  elseif what == "copy-command" then copy_last_command(false)
  else ranma.notify("marks: list, prev, next, copy or copy-command") end
end

ranma.command("marks", run, {
  desc = "jump between prompts, copy a command's output",
  args = "[list|prev|next|copy|copy-command]",
  complete = { "list", "prev", "next", "copy", "copy-command" },
})

-- For binds of your own: ranma.emit("marks", "prev").
ranma.on("user:marks", run)
