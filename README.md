# marks.ranma

A plugin for [ranma](https://github.com/masshirodev/ranma), the terminal tiling window manager: the shell's prompts as places in a pane. Jump from one to the next, copy a command's output without copy mode, and list the commands still in the scrollback.

## Install

With [hako](https://github.com/masshirodev/hako.ranma), in `~/.config/ranma/lua/plugins/marks.lua`:

```lua
return { "masshirodev/marks.ranma" }
```

Or by hand, as ranma loads any package under `pack/*/start/`:

```sh
git clone https://github.com/masshirodev/marks.ranma ~/.config/ranma/pack/plugins/start/marks.ranma
```

Needs: ranma 0.2.1 or newer (the first with `pane:marks()`), and a shell that marks its prompts (below).

## What it does

```text
marks: the shell's prompts as places in a pane. Jump from one to the next,
copy a command's output without copy mode, and list the commands still in
the scrollback.

It reads pane:marks(), so the shell has to mark its prompts and commands
with OSC 133: the zsh lines under `command_finished` in ranma's CONFIG.md,
or the README's bash lines. A pane whose shell sends none says so in a
toast (and on the list's status), and nothing else happens.

leader ' is a folder (+marks), ' being vim's key for marks:
  ' k    the previous prompt, scrolled to the top of the view; then MARKS
  ' j    the next prompt (past the newest, the bottom); then MARKS, even
         when there was nowhere to go
  ' y    copy the output of the last command that finished
  ' c    copy that command's command line
  ' l    the list: the commands in the scrollback, newest first, with their
         exit status, how long they ran (when ranma saw them finish) and the
         end of their output. On it:
           enter  jump to it (then MARKS)    y  copy its output
           c      copy its command line      r  read the pane again
MARKS is a mode (the bar says MARKS; esc or enter leaves it):
  k j ↑ ↓  the previous / next prompt      g G  the oldest / the bottom
  y        copy the output of the command at the prompt jumped to
  c        copy its command line           v    copy mode at that prompt
  l        the list
:marks [list|prev|next|copy|copy-command] in the palette does the same,
and so does ranma.emit("marks", "prev") from a bind of your own.

' k and ' j start from the bottom of the pane. MARKS mode, the palette and
the event go on from the prompt last jumped to, until a command starts in
that pane (ranma cannot tell a plugin how far a pane is scrolled).
From the bottom, the previous prompt is the newest one above the screen.

A command is a prompt whose command ran; an Enter on an empty line is not
one. Its output is its lines from where it started printing to the next
prompt, blank rows at the end left out; a row as wide as the pane is taken
as wrapped and joined to the next. The command line is read off the screen
and the prompt cut from it: up to the first `$ `, `% `, `# `, `> `, `❯ `,
`➜ `, `» ` or `λ ` on its first line that has one, or what marks.prompt
matches. How long a command ran comes from the command_finished hook, kept
for each pane until the configuration reloads, and is shown only where the
exit statuses line up, newest first; a command that finished before a
reload shows none. A shell that does not say how a command ended shows ·
for its status, and no duration.
Options (settings panel, "marks" group): marks.prompt, marks.max,
marks.preview.

Needs ranma 0.2.1 or newer, the first with pane:marks().
ranma's plugin API: https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md ("Pane
handles", "Screens", "Modes", "Hooks").
```

## Shell integration

marks reads where prompts, command lines and output are from the OSC 133 marks the shell prints. A shell that sends none gets a toast saying so, and nothing else happens.

**zsh**: the lines under `command_finished` in ranma's CONFIG.md. They work as they are under powerlevel10k, its transient prompt included.

**bash** (4.4 or later, for `PS0`), in `.bashrc`:

```bash
PS0='\e]133;C\a'
PROMPT_COMMAND='printf "\e]133;D;%s\a\e]133;A\a" "$?"'${PROMPT_COMMAND:+"; $PROMPT_COMMAND"}
```

The same marks make ranma's `command_started` and `command_finished` hooks work. A shell that sends prompts but never says how a command ended still works: each command ends where the next prompt starts, and the list shows `·` for its status.

## Binds and commands

| Keys | |
| --- | --- |
| `leader '` | The `+marks` folder, listed under `plugins` in the which-key hint. |
| `leader ' k` | The previous prompt, at the top of the view, then MARKS mode. |
| `leader ' j` | The next prompt, then MARKS mode. |
| `leader ' y` | Copy the output of the last command that finished. |
| `leader ' c` | Copy its command line. |
| `leader ' l` | The list of the commands in the scrollback. |
| `:marks [list\|prev\|next\|copy\|copy-command]` | The same from the palette (`leader :`). |
| `ranma.emit("marks", "prev")` | The same from a bind of your own. |

In MARKS mode: `k` `j` `↑` `↓` step, `g` goes to the oldest prompt and `G` to the bottom, `y` copies the output of the command at the prompt, `c` its command line, `v` enters copy mode there, `l` opens the list, and `esc` or `enter` leaves.

On the list: `enter` jumps to the selected command's prompt (then MARKS mode), `y` copies its output, `c` its command line, `r` reads the pane again, `/` filters, `o` opens these options.

## Options

In ranma's settings panel under `marks`, or with hako's `opts` (`{ "masshirodev/marks.ranma", opts = { ... } }`), or `ranma.set { marks = { ... } }`.

| Option | Default | |
| --- | --- | --- |
| `marks.prompt` | `""` | A Lua pattern matching the prompt before a command line, such as `"^.-%$ "`. Empty: up to the first `$`, `%`, `#`, `>`, `❯`, `➜`, `»` or `λ` and a space. |
| `marks.max` | `200` | The most commands the list shows, newest first. |
| `marks.preview` | `8` | The last lines of output the list shows under the selected command. |

## License

MIT or Apache-2.0, as ranma.
