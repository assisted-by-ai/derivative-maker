## Bash Style Guide (AI-Assisted)

This guide collects the bash style choices applied to scripts under
the assisted-by-ai org. Brief by design; the goal is "readable by both
human reviewers and AI tools without a 50-page rulebook."

## Strict shell options

Every new script starts with:

```
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose
```

`inherit_errexit` makes `errexit` apply inside `$( ... )` substitutions
(off by default in bash 5.x). `shift_verbose` makes `shift` log when
called past argv end.

## Variables

* All variable expansions use `${var}`, never bare `$var`.
* Do not initialize a variable to `${var:-}` unless `set -o nounset`
  forces it. `${var:-}` is a real signal that the variable may not be
  defined; using it where it is defined hides actual init-order bugs.
* `local var1 var2 var3` declares all locals on a single line at the
  top of the function. Then assign on subsequent lines:

```
foo() {
   local owner repo patch

   owner="$1"
   repo="$2"

   ## ... logic
}
```

* Never use `local x="$(cmd)"`. `local` always exits 0, so `cmd`'s
  failure is masked. Declare with `local x` then assign on the next
  line.
* Globals at the top of the script, grouped, with one comment block
  per knob and a blank line between assignments.
* Variable names in messages should be wrapped in single quotes so
  trailing/leading whitespace shows: `printf '%s\n' "error: '${path}'
  not found" >&2`.

## printf

Always `printf '%s\n' "..."`. The format string is fixed; everything
else goes in the data string. No `%d`, no `%q` (except where you
genuinely need shell-escaping), no extra `\n` in the format.

* Multi-line block: ONE quoted string with embedded newlines, so only
  one open/close quote pair.
* Multiple distinct lines: one `printf '%s\n' "..."` per line.
* Blank line: `printf '%s\n' ""` (not `\n` in the format).

## Flags

* Long option names whenever the tool supports one: `--quiet`,
  `--ignore-case`, `--lines=1`, `--unique`. `wc --lines`, `sort
  --unique`, etc.
* Combined short flags get split: `rm -rf` -> `rm -r -f`,
  `declare -gA` -> `declare -g -A`.
* End-of-options separator `--` everywhere the tool supports one and
  positional args follow flags. Verified working before adding:
  `git`, `grep`, `sed`, `tr`, `jq`, `head`, `tail`, `stat`,
  `mktemp`, `wc`, `sort`, `cat`, `rm`, `safe-rm`, `mkdir`, `find`.

## Case statements

* `;;` on its own line, never trailing the last statement.
* Each statement on its own line; multi-statement single-line arms
  are split.
* Reserved-name patterns and metachar-looking literals are quoted:
  `'.git'` not `.git`, `'-'*` not `-*`.

```
case "${kind}" in
   repo)
      max_len="${MAX_REPO}"
      ;;
   user)
      max_len="${MAX_USER}"
      ;;
esac
```

## Sourcing helper-scripts

```
source "${HELPER_SCRIPTS_PATH:-}"/usr/libexec/helper-scripts/<file>
```

Empty `${HELPER_SCRIPTS_PATH}` -> system install at
`/usr/libexec/helper-scripts/`. A caller running with helper-scripts
as a submodule sets the variable to the submodule path.

Each consumer sources every helper-scripts file it uses directly.
Do not rely on transitive sourcing (one helper-scripts file pulling
in another). For example, `log_run_die.sh` happens to source
`strings.bsh` for its own use; if your script also calls
`is_whole_number` from `strings.bsh`, source `strings.bsh` itself
even if `log_run_die.sh` is already sourced. Otherwise a future
refactor that drops the transitive source breaks you silently.

`wc` invocations should be preceded by sourcing `wc-test.sh` so a
broken `wc` binary fails loudly rather than silently producing an
empty count.

Reuse strings.bsh's `is_whole_number`, `validate_safe_filename`,
`check_is_alpha_numeric` etc. before reimplementing.

## Errors and logging

Use `log` and `die` from `helper-scripts/log_run_die.sh`:

```
log error "couldn't read '${path}'"   ## log only
log warn  "..."
log info  "..."
die 1 "fatal: ..."                     ## logs error then exit 1
[ "$#" -ge 2 ] || die 64 "missing value for --include"
```

`die <code> <msg>` is the one-liner for "log error then exit." Use
it for top-level fatal sites (parser guards, missing prerequisites,
unrecoverable state). Inside a function that should return rather
than exit, use `log error "..."; return N` instead.

Don't write `printf '%s\n' 'error: ...' >&2; exit N`; that's the
ad-hoc form `die` replaces.

## File deletion

Use `safe-rm` instead of `rm`. Long flag form: `safe-rm --force --`
or `safe-rm --recursive --force --`. `safe-rm` consults a blocklist
before deleting.

## Traps

Trap targets are standalone named functions, never inline command
strings. The function references variables from the calling scope
via bash dynamic scoping; the trap is registered AFTER those
variables are initialized so the reference is `nounset`-safe with
no `${var:-}` default.

```
foo_cleanup_tmp() {
   safe-rm --force -- "${tmp_file}"
}

foo() {
   local tmp_file

   tmp_file="$(mktemp)"
   trap foo_cleanup_tmp RETURN

   ## ... use ${tmp_file}
}
```

## Null command

`true` instead of `:` for no-op placeholders. Pass a descriptive
message so xtrace logs convey intent:

```
true "INFO: ghorg_api: HTTP 429 - will retry"
```

Bare `true > "${file}"` is fine for "truncate file". `while true` is
fine for an infinite loop.

## printf inline command substitution

Pre-compute substitutions into a named variable instead of inlining:

```
## avoid:
printf '%s\n' "warn: $(my_helper "${value}")"

## prefer:
result="$(my_helper "${value}")"
printf '%s\n' "warn: ${result}"
```

Reads better, surfaces intermediate names, and stops printf format
strings from growing into expressions.

## API-derived strings (untrusted bytes)

Treat every byte returned by an external service as untrusted:

* Identifier sinks (URL paths, file paths, command-line arguments):
  pass through a strict allowlist validator (e.g. `^[A-Za-z0-9._-]+$`)
  or a numeric-only regex with length cap before use.
* Display sinks (printf to stdout/stderr): pass through a sanitizer
  (e.g. `sanitize-string`) that strips ANSI escapes, control chars,
  HTML markup, and truncates oversized payloads.
* Don't sanitize the raw API body before parsing - the parser (jq)
  is the schema validator. Sanitize after extraction, before display.
