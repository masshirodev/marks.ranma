# AGENTS.md

marks.ranma is a ranma plugin in Lua: `plugin/marks.lua` is all of it, and
its header comment is the reference that `README.md` repeats. ranma's API is
https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md (`ranma --dump-types` prints it as LuaLS annotations).

- Push to `main`.
- A change to what it does changes the header comment and `README.md` in the
  same commit, and an option goes in the README's table.
- Everything rests on `pane:marks()`, which first shipped in ranma
  the release after 0.2.0. Its marks are tags on the first cell printed after each
  one, and a shell that draws over that cell loses them: commands with no C
  (zsh's `PROMPT_SP`), with no D (a redrawn prompt, p10k), with a B on a later
  line (p10k's transient prompt), and an empty mark before each prompt (zsh
  printing a PS1 that holds the marks twice). `read()` is where each of those
  is handled; keep new cases there.
- There is no API for how far a pane is scrolled, so stepping keeps its own
  place (`cursor`: how many commands are newer) and forgets it when a
  command starts in the pane.
- Test against real shells in a private ranma server (never the default
  socket): zsh with the CONFIG.md lines, zsh with the README's PS1 lines,
  bash, powerlevel10k, a shell with no marks, `clear`, a resize, and a long
  output that scrolls.
- Check it loads: `ranma --check-config` lists every plugin and why one failed;
  `ranma lua` runs code in the live server.
  CI (`.github/workflows/ci.yml`) loads it into the latest ranma release on
  every push and fails if it does not.
- `AGENTS.local.md` (gitignored) carries what is true of one checkout on one
  machine. Never commit it.
