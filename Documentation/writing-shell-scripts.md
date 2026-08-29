# Writing shell scripts

This is the Cursor Agent Skill used for every script in this repository.
The same files live in `.cursor/skills/writing-shell-scripts/` so an agent
working in this tree follows the same rules.  The `usage()` wording lives
in [usage-template.md](usage-template.md).

Apply this skill whenever writing or editing a shell script.

## Before writing anything

Do not make assumptions. Ask as many questions as needed to gain agreement on the outcome.

If the user has missed something, or if relevant information is missing, inform them so they can decide. Typical gaps: interpreter, sourced vs executed, target OS (`/bin/sh` is dash on Void), man page, `--version`, color output, whether existing scripts should be rewritten.

**Always ask which interpreter** before writing a new script:

- Recommend `sh` (POSIX) unless they already said otherwise.
- Offer `bash` if the design needs `local`, arrays, `[[ ]]`, or other bash features.
- Exception: zsh plugin — then zsh, not POSIX.

Do not start the file until they agree.

## Shebang

Always use `#!/usr/bin/env` then either `sh` or `bash`, unless writing a zsh plugin.

```
#!/usr/bin/env sh
#!/usr/bin/env bash
```

Correct form is `#!/usr/bin/env`, not `#!/usr/bin env`.

Zsh plugin: `#!/usr/bin/env zsh` only when they said it is a zsh plugin.

## POSIX by default

All scripts need to be POSIX compatible unless the user explicitly says that you do not have to.

- Default dialect: POSIX `sh`. Run `shellcheck -s sh`.
- `local` is not POSIX. If the script needs many functions with `local`, ask to switch to bash, then use `#!/usr/bin/env bash` and `shellcheck -s bash`.
- Bash-only (need agreement first): `local`, arrays, `[[ ]]`, `mapfile`, `declare`, process substitution.

## Strict mode

- POSIX scripts: `set -eu` immediately after the shebang/comments.
- Bash scripts: `set -euo pipefail` immediately after the shebang/comments.
- `pipefail` is bash-only. Do not use it in POSIX `sh`.
- If the file can be sourced, enable these options for the run, then restore the caller's settings (same idea as nounset in `path_cleaner.sh`). Do not leave `set -e` on in the user's interactive shell.
- Commands that are allowed to fail must be explicit: `cmd || true`, or test in `if`. Watch pipelines: with `pipefail`, `grep` with no match aborts the script unless handled. A function that ends with a failing test (`[ -n "$x" ] && printf`) returns 1 and will abort the caller — end those functions with `return 0`.

## usage()

All scripts need to have a function for usage and the usage must have the same wording as coreutils.

See [usage-template.md](usage-template.md). Required pieces:

- `Usage: PROG [OPTION]... [ARG]`
- One-line description
- `Mandatory arguments to long options are mandatory for short options too.`
- Options as `  -x, --long          description` (aligned)
- `-h, --help            display this help and exit`
- Unknown option: `PROG: unrecognized option …` then `Try 'PROG --help' for more information.` (exit 2)

Do not add `--version` or a man page unless you asked and they said yes.

## Functions

Create functions everywhere you can, avoid functions only if you have to refactor frequently.

Prefer small named functions over inline blocks. Keep a linear `main` (or equivalent) that only parses args and calls functions.

## Sourced scripts

If the file can be sourced, every helper function and temporary global must be prefixed (`_pc_`, or the script's own prefix) and unset before returning. The only state that may remain is what the user asked to change (for example `PATH`). Do not leave `usage`, `declare -A`, or color variables in the interactive shell.

## Output and color

- `--help` and the program's data go to stdout.
- Diagnostics, prompts, progress, and errors go to stderr.
- Color only when stdout is a tty and `NO_COLOR` is unset or empty (https://no-color.org).

## Temporary files

Every `mktemp` path is removed on `EXIT` and on normal finish. Register temps in one list and one trap; do not leave a naked `mktemp` without cleanup.

If the file can be sourced, save the caller's `EXIT` trap (`trap -p EXIT`), install yours, then restore (or `trap - EXIT` if the caller had none). Do not leave your trap in the interactive shell.

## Locale

Export `LC_ALL=C` for grep, sort, and string comparisons so the user's locale cannot change results.

If the file can be sourced, save and restore `LC_ALL` (unset it if the caller did not have it). Do not leave `LC_ALL=C` in the interactive shell.

## PATH hash and operand `--`

After changing `PATH` in the current shell, refresh the command lookup cache: `hash -r` (bash / POSIX) or `rehash` (zsh). Skip this for `PATH=... command` prefixes on a child process.

Pass `--` before operand paths to `mv`, `cp`, `rm`, `cd`, `stat`, `readlink`, `basename`, `dirname`, `tail`, and similar, so a path that starts with `-` is not taken as an option. Do not pass `--` to `awk` unless it is GNU awk; other awks treat `--` as a filename.

## Aliases and functions

Executed scripts (not sourced): `unalias -a` and `unset -f` on external tools the script calls (`rm`, `mv`, `grep`, …) so a user alias or function cannot hijack them. Skip both when the file is sourced.

## printf only

Use `printf` for all output. Do not use `echo` (not portable; `echo -e` and flags differ by shell).

## Constants

Mark constants `readonly` after assignment (`PROGNAME`, timeouts, markers, baseline PATH). Do not use `readonly` in a sourced file (it would leak into the interactive shell).

## Bounded traces

Login-shell xtrace must not hang forever. Wrap it with `timeout` (default 20 seconds). If `timeout` is missing, say so and run unbounded only after that, or fail. On timeout, print a diagnostic to stderr and exit 1.

## Exit status

Same as coreutils:

- `0` — success (including `--help`)
- `1` — runtime failure
- `2` — usage error (unrecognized option, bad invocation)

## shellcheck and shfmt

Every time you write a script you need to pass it through shellcheck and make sure it passes 100%, then format with shfmt.

1. Write or edit the script.
2. Run: `shellcheck -s sh FILE` or `shellcheck -s bash FILE` (match the agreed dialect).
3. Fix every error and warning. Do not finish with findings.
4. Do not add `# shellcheck disable=…` unless the user approved that specific code.
5. If shellcheck is missing, install it or say so; do not skip the pass.
6. Run `shfmt -w -i 4 -ci FILE` (4-space indent, indent switch cases). If shfmt is missing, install it or say so; do not skip the pass.

## Existing scripts

When asked to rewrite existing scripts to this standard, ask per file only if a constraint conflicts (for example a file must be sourced from both bash and zsh). Otherwise apply this skill and run shellcheck.

## Checklist

- [ ] Interpreter agreed (asked)
- [ ] Missing decisions surfaced to the user
- [ ] `#!/usr/bin/env sh` or `#!/usr/bin/env bash` (or zsh plugin)
- [ ] POSIX unless they explicitly allowed bash/zsh
- [ ] `set -eu` (POSIX) or `set -euo pipefail` (bash); restore if sourced
- [ ] `usage()` with coreutils wording
- [ ] Functions used wherever they do not block frequent refactoring
- [ ] Sourced scripts: prefixed helpers, all unset except intended state
- [ ] stdout = data/--help; stderr = diagnostics; honor NO_COLOR
- [ ] Exit 0 / 1 / 2 as coreutils
- [ ] Every mktemp on an EXIT trap; restore trap if sourced
- [ ] `LC_ALL=C` for text processing; restore if sourced
- [ ] `hash -r` / `rehash` after changing the current shell's PATH
- [ ] `--` before operand paths on mv/cp/rm/cd and similar
- [ ] Executed scripts: `unalias -a` and `unset -f` on called tools
- [ ] `printf` only, no `echo`
- [ ] `readonly` constants when not sourced
- [ ] Login-shell xtrace wrapped in `timeout`
- [ ] `shellcheck -s <dialect>` exit 0, zero warnings, no unapproved disables
- [ ] `shfmt -w -i 4 -ci` applied
