# CLAUDE.md

## Purpose

`gtty` is a Nushell module that manages **Ghostty** workspace surface layouts via the
[Ghostty AppleScript API](https://ghostty.org/docs/features/applescript#broadcast-a-command-to-every-terminal) (`sdef /Applications/Ghostty.app/`).

It exposes three subcommands: `gtty enter`, `gtty exit`, and `gtty siblings`.

## Module Structure

```
lib/gtty/
  mod.nu         — re-exports enter.nu, exit.nu, siblings.nu
  enter.nu       — gtty enter    (export def main)
  exit.nu        — gtty exit     (export def main)
  siblings.nu    — gtty siblings (export def main)
  completion.nu  — shared completers: _panes, _actions, _signals, _readme
```

`mod.nu` contains only `export use` lines. Each subcommand file defines
`export def main` — Nushell maps the filename to the subcommand name.

## Completions

`completion.nu` is imported by `enter.nu` and `siblings.nu` via `use completion.nu *`.
It must not import from outside the `gtty/` directory — `../mood.nu` is a `mij`
internal and is not available here.

### \_panes cache

`_panes` queries Ghostty via AppleScript and caches the result in `stor`
(Nushell's in-memory SQLite) under table `GTTY_SURFACES` with a 60-second TTL.
The cache is process-scoped — it works across tab completions in an interactive
shell but is lost on shell exit. Each `nu --no-config-file` invocation starts
with an empty cache.

### Cache format

The raw cached string is newline-separated lines:

```
ME:<index>
<index>|<tty_device>|<pane_name>
```

Pipe (`|`) is used as the field separator to avoid conflicts with `:` in
Kakoune pane titles.

### AppleScript variable naming

The local variable for reading a pane's TTY must be named `pane_tty`, not
`tty`. AppleScript reads `set tty to tty of t` as assignment (setting the
property), not a read — this causes a `-10006` error from Ghostty.

## Testing Completions

Completers can be tested directly without a running Ghostty instance by loading
`completion.nu` in isolation and seeding the `stor` cache manually.

### \_panes (live, requires Ghostty)

```nushell
nu --no-config-file -c "use ./lib/gtty/completion.nu *; _panes | get completions"
```

### \_panes (offline, seeded cache)

```nushell
nu --no-config-file -c "
    use ./lib/gtty/completion.nu *
    stor delete --table-name GTTY_SURFACES
    stor create --table-name GTTY_SURFACES --columns { raw: str, cached_at: datetime }
    { raw: \"ME:2\n1|/dev/ttys001|kak README.md\n3|/dev/ttys003|zzz\n4|/dev/ttys004|gitui\n\",
      cached_at: (date now) } | stor insert --table-name GTTY_SURFACES
    _panes | get completions
"
```

Adjust the `ME:` index and sibling lines to simulate different pane layouts.
Set `cached_at` in the past to test TTL expiry:

```nushell
cached_at: ((date now) - 120sec)
```

### \_actions and \_signals (static, no dependencies)

```nushell
nu --no-config-file -c "use ./lib/gtty/completion.nu *; _actions | get completions"
nu --no-config-file -c "use ./lib/gtty/completion.nu *; _signals | get completions"
```

### Notes

- Each `nu --no-config-file` invocation starts with an empty `stor`, so the
  cache is never warm between test runs — the live Ghostty path is always taken
  unless you seed it explicitly in the same `-c` block.
- Tab completion in an interactive shell is the only way to verify the full
  round-trip including Nushell's completer integration.

## Conventions

- All private helpers in each `.nu` file use plain names (no `gtty_` prefix)
  because unexported `def`s are file-scoped and do not leak through `export use`.
- `ps` calls must not use shell redirects like `2>/dev/null` — Nushell passes
  them as literal arguments to the external command.
- Tint colours: `TINT_DIM = "#1c1214"`, `TINT_FLASH = "#2a1015"` (dark
  red tones used to visually mark a targeted pane).
- The `--interval` default on `gtty siblings` is `5sec`; `--max` defaults to
  `1984` (effectively unlimited for normal use).
