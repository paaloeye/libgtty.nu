# CLAUDE.md

## Purpose

`gtty` is a Nushell module that manages **Ghostty** workspace surface layouts via the
[Ghostty AppleScript API](https://ghostty.org/docs/features/applescript#broadcast-a-command-to-every-terminal) (`sdef /Applications/Ghostty.app/`).

It exposes three subcommands: `gtty enter`, `gtty leave`, and `gtty surface siblings`.

## IMPORTANT

> [!WARNING]
> These rules override default behaviour. Follow them exactly when working with this codebase. Violations may cause
> linter failures or break pre-commit hooks.

- ALWAYS read [GOTCHA.md](./GOTCHA.md) first
- PREFER British English over American English spelling and grammar except in **inline code** sections
- USE Markdown banners ([see below](#a-tour-of-banners))
- Files and Directories MUST NOT have **dashes** in names/paths (use **underscore** instead)
- NEVER use Git LFS
- USE Emoji in [README.md](./README.md) or **docs/\*.md** with care. NOT MUCH.
- ALL development scripts use Nushell (\*.nu) - install nushell for development workflow
- ALWAYS use `[x]` or `[ ]` instead of ✅ / 🔲 / for checkmarks
- NEVER use `[x]` or `[ ]` in Markdown tables; USE ✅ / 🔲 / instead. **Reason**: it's not supported
- PREFER [GitHub Emoji API](https://api.github.com/emojis) over Unicode Emoji
- ALWAYS add footer to new Markdown files with a AI generated content banner (!CAUTION)
- PREFER 120 characters per line

## A Tour of Banners

> [!NOTE]
> Highlights information that users should take into account, even when skimming.

> [!TIP]
> Optional information to help a user be more successful.

> [!IMPORTANT]
> Crucial information necessary for users to succeed.

> [!WARNING]
> Critical content demanding immediate user attention due to potential risks.

> [!CAUTION]
> Negative potential consequences of an action.

## Commit Messages

Follow conventional commit format with detailed explanations and proper sign-off.

### Format

```
<type>(<scope>): <subject>

<detailed body explaining what and why in bullet points>

BREAKING CHANGE: <description if applicable>

🤖 Generated with [$(ai.nu agent get-caller-identity --key .name)]($(ai.nu agent get-caller-identity --key .url))

Co-Authored-By: $(ai.nu model --key .name) <gemini-code-assist@google.com>
Co-Authored-By: $(ai.nu agent get-caller-identity)
Signed-Off-By: Paal Øye-Strømme <paal.o.eye@gmail.com>
```

> [!IMPORTANT]
> The `$(ai.nu agent get-caller-identity)` footer line requires shell substitution. Use an **unquoted** heredoc (`EOF`, not `'EOF'`) so the shell expands it:
>
> ```bash
> git commit -m "$(cat <<EOF
> <message>
>
> Co-Authored-By: $(ai.nu agent get-caller-identity)
> EOF
> )"
> ```

### Best Practices

- **Type**: Use `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`
- **Scope**: Specify affected module/component (e.g., `supabase`, `components`, `hooks`)
- **Subject**: Imperative mood, no period, max 50 characters
- **Body**: Explain the what and why, not how. Include context and reasoning in bullet points using "-" as for item mark
- **Breaking Changes**: Always document with `BREAKING CHANGE:` footer
- **Sign-off**: Include Agent attribution for AI-generated commits in `Co-Authored-By` and the main committer in `Signed-Off-By`

### Examples

```bash
feat(supabase): add verify-email function

- added verify-email Edge function to confirm users's email
- added tests

fix(components): add toaster

- toaster is used for notification
- no testes yet

docs:: update module usage examples and references

- for consistency
- improved readability

refactor(hooks): change useToast

- fixes #1
- added extra options
```

## Conventions

- **We're Dutch honest**
- British English throughout (colour, licence, behaviour, etc.)
- No dashes in file or directory names — use underscores
- Follow conventional commit format

## Module Structure

```text
lib/gtty/
  mod.nu            — re-exports enter.nu, leave.nu, surface/
  enter.nu          — gtty enter (export def main)
  leave.nu          — gtty leave (export def main)
  completion.nu     — shared completers: _panes, _actions, _signals, _ai, _readme
  surface/
    mod.nu          — re-exports lib.nu, siblings.nu, broadcast.nu
    siblings.nu     — gtty surface siblings (export def main)
    broadcast.nu    — gtty surface broadcast (export def main)
    lib.nu          — tint/flash helpers and TINT_DIM / TINT_FLASH constants
```

`mod.nu` contains only `export use` lines. Each subcommand file defines
`export def main` — Nushell maps the filename to the subcommand name.

## Completions

`completion.nu` is imported by `enter.nu` and `surface/siblings.nu` via `use completion.nu *`.
It must not import from outside the `gtty/` directory.

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
nu --no-config-file -c "use ./completion.nu *; _panes | get completions"
```

### \_panes (offline, seeded cache)

```nushell
nu --no-config-file -c "
    use ./completion.nu *
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
nu --no-config-file -c "use ./completion.nu *; _actions | get completions"
nu --no-config-file -c "use ./completion.nu *; _signals | get completions"
```

### Notes

- Each `nu --no-config-file` invocation starts with an empty `stor`, so the
  cache is never warm between test runs — the live Ghostty path is always taken
  unless you seed it explicitly in the same `-c` block.
- Tab completion in an interactive shell is the only way to verify the full
  round-trip including Nushell's completer integration.

## Formatting & Development

To format files (Swift and docs):

```bash
bun run fmt
```

To check documentation formatting:

```bash
bun run fmt:docs:check
```

## Conventions

- **We're Dutch honest**
- British English throughout (colour, licence, behaviour, etc.) except in inline code sections.
- No dashes in file or directory names — use underscores.
- Follow conventional commit format.
- All private helpers in each `.nu` file use plain names (no `gtty_` prefix)
  because unexported `def`s are file-scoped and do not leak through `export use`.
- `ps` calls must not use shell redirects like `2>/dev/null` — Nushell passes
  them as literal arguments to the external command.
- Tint colours: `TINT_DIM = "#1c1214"`, `TINT_FLASH = "#2a1015"` (dark red tones used to visually mark a targeted pane).
- The `--interval` default on `gtty surface siblings` is `5sec`; `--max` defaults to `1984` (effectively unlimited for normal use).
