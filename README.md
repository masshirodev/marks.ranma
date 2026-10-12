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

Needs: the first ranma release after 0.2.0, which has `pane:marks()`, and a shell that marks its prompts (below).

## What it does

```text
marks: the shell's prompts as places in a pane. Jump from one to the next,
copy a command's output without copy mode, and list the commands still in
the scrollback.

It reads pane:marks(), so the shell has to mark its prompts and commands
with OSC 133: the README's "Shell integration" has zsh, bash and
powerlevel10k. A pane with no marks says why in a toast (and on the list's
status), its shell sending none or drawing its prompt over them, and
nothing else happens.

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
reload shows none. A shell whose marks lose their exit status (p10k's)
shows · for it, and no durations.
Options (settings panel, "marks" group): marks.prompt, marks.max,
marks.preview.

Needs a ranma with pane:marks(): the first release after 0.2.0.
ranma's plugin API: https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md ("Pane
handles", "Screens", "Modes", "Hooks").
```

## Shell integration

ranma learns where prompts, command lines and output are from the OSC 133 marks the shell prints, and keeps each one on the first character printed after it. A shell that later draws over that character takes the mark with it. That happens when the shell redraws its prompt: zsh and bash do on a resize, and powerlevel10k does on every prompt. So the marks belong inside the prompt, which sends them again each time it is drawn.

**zsh.** The lines under `command_finished` in ranma's CONFIG.md work until a prompt is redrawn: that prompt's marks are lost, and the command before it runs on into the next. This sends the end of a command and the start of a prompt from the prompt itself:

```zsh
_ranma_mark_start() { print -n "\e]133;C\a"; }
preexec_functions+=(_ranma_mark_start)
PS1=$'%{\e]133;D;%?\a\e]133;A\a%}'$PS1
```

The `command_finished` and `command_started` hooks work the same with it. A command that prints nothing loses its output mark to zsh's `PROMPT_SP` either way; marks still lists it, from its command line.

**bash** (4.4 or later, for `PS0`):

```bash
PROMPT_COMMAND="_ranma_s=\$?${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
PS1='\[\e]133;D;${_ranma_s}\a\e]133;A\a\]'"$PS1"
PS0='\e]133;C\a'
```

**powerlevel10k with its transient prompt sees nothing.** With the CONFIG.md lines alone, a p10k prompt is drawn over its marks every time, so marks finds none in the pane and says so. That is a ranma bug (card c239, "pane:marks() loses marks when the shell redraws its prompt (empty under p10k)"), and this stays true until ranma fixes it. p10k rebuilds `PS1` before every prompt, so the zsh lines above do not help under it. Turn on p10k's own marks in `~/.p10k.zsh` instead (alongside the CONFIG.md lines is fine):

```zsh
typeset -g POWERLEVEL9K_TERM_SHELL_INTEGRATION=true
```

Prompts, command lines and output then come through, but exit statuses do not: p10k sends a command's end before a prompt it then redraws. The list shows `·` for the status, and no durations.

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
