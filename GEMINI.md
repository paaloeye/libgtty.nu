# GEMINI.md

## Purpose

`gtty` is a Nushell module that manages Ghostty workspace pane layouts via the
Ghostty AppleScript API (`sdef /Applications/Ghostty.app/`). It exposes three
subcommands: `gtty enter`, `gtty leave`, and `gtty surface siblings`.

## Antigravity (agy) & Gemini Context

As a Gemini agent (via Antigravity/`agy`), note the following integration points:

- `libgtty` supports launching `agy` directly in a pane using `gtty enter --ai agy`.
- The AI binary is resolved via the `$env.ANTIGRAVITY_CLI` environment variable (defaults to `ag`).
- When writing temporary scratch scripts or files for testing, consider using the Antigravity artifact directory (`<appDataDir>/brain/<conversation-id>/scratch/`).
- Use standard GitHub-flavored markdown and Antigravity features like artifacts for extensive reporting or logs.

## Module Structure

```text
lib/gtty/
  mod.nu            — re-exports enter.nu, leave.nu, surface/
  enter.nu          — gtty enter (export def main)
  leave.nu          — gtty leave (export def main)
  completion.nu     — shared completers: _panes, _actions, _signals, _ai, _readme
  surface/
    mod.nu          — re-exports lib.nu, siblings.nu
    siblings.nu     — gtty surface siblings (export def main)
    lib.nu          — tint/flash helpers and TINT_DIM / TINT_FLASH constants
```

`mod.nu` contains only `export use` lines. Each subcommand file defines
`export def main` — Nushell maps the filename to the subcommand name.

## Completions

`completion.nu` is imported by `enter.nu` and `surface/siblings.nu` via `use completion.nu *`.

### \_panes cache

`_panes` queries Ghostty via AppleScript and caches the result in `stor`
(Nushell's in-memory SQLite) under table `GTTY_SURFACES` with a 60-second TTL.
The cache is process-scoped — it works across tab completions in an interactive
shell but is lost on shell exit. Each `nu --no-config-file` invocation starts
with an empty cache.

### Cache format

The raw cached string is newline-separated lines:

```text
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
- The `--interval` default on `gtty surface siblings` is `5sec`; `--max` defaults to
  `1984` (effectively unlimited for normal use).
