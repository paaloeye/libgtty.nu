# libgtty

Nushell module for managing [Ghostty](https://ghostty.org/) workspace surfaces layouts
via the [Ghostty AppleScript API](https://ghostty.org/docs/features/applescript).

## Commands

### `gtty enter`

Build a 4-surfaces workspace layout in the current tab.

```
gtty enter [--file <path>] [--ai <provider>] [--ai-session <id>]
```

```
[t1: nnn <file> ]   [t3: nnn    ]
[t2: <ai>       ]   [t4: gitui  ]
```

| Flag           | Default      | Description                                                     |
| -------------- | ------------ | --------------------------------------------------------------- |
| `--file`       | first README | File to open in `nnn` (default: first existing README)          |
| `--ai`         | `agy`        | AI provider to launch in t2: `agy`, `claude`, `gemini`, or `pi` |
| `--ai-session` | `""`         | Session ID to resume with `--resume` (provider-agnostic)        |

The AI binary is resolved from the environment:

| Provider  | Env var                 | Default binary |
| --------- | ----------------------- | -------------- |
| `agy`     | `$env.ANTIGRAVITY_CLI` | `ag`           |
| `claude`  | `$env.CLAUDE`          | `cl`           |
| `gemini`  | `$env.GEMINI`          | `gi`           |
| `pi`      | `$env.PI`              | `pi`           |

> [!NOTE]
> The AI command is typed into t2 but **not sent**

### `gtty leave`

Close the 3 sibling panes created by `gtty enter`. Requires exactly 4 panes in
the current tab. The tab itself is not closed.

```
gtty leave [--force]
```

| Flag      | Description              |
| --------- | ------------------------ |
| `--force` | Skip confirmation prompt |

If the focused pane is zoomed (`cmd+shift+enter`), it is automatically unzoomed
before closing siblings so all panes are reachable via AppleScript.

### `gtty surface siblings`

Perform a one-shot or looping action on a sibling pane by relative offset.

```
gtty surface siblings --offset <offset> --action <action> [options]
```

| Flag         | Default  | Description                                         |
| ------------ | -------- | --------------------------------------------------- |
| `--offset`   | required | Relative offset from focused pane (e.g. `+1`, `-1`) |
| `--action`   | required | `kill`, `auto-accept`, or `focus`                   |
| `--args`     | `""`     | `key=value` pairs: `signal=term,confirm=true`       |
| `--max`      | `1984`   | Maximum sends (`auto-accept` only)                  |
| `--interval` | `5sec`   | Interval between sends (`auto-accept` only)         |

#### Actions

**`kill`** — Send a signal to all processes on the target pane's TTY.

```nushell
gtty surface siblings --offset +1 --action kill
gtty surface siblings --offset +1 --action kill --args signal=hup,confirm=false
```

**`auto-accept`** — Repeatedly send **Enter** to a _Agent surface_ to
auto-accept prompts. Tints the target pane dark red while armed.
Stop with `Ctrl+C`.

```nushell
gtty surface siblings --offset -1 --action auto-accept
gtty surface siblings --offset -1 --action auto-accept --max 10 --interval 10sec
```

**`focus`** — Move keyboard focus to the target pane with a brief flash
confirmation.

```nushell
gtty surface siblings --offset +1 --action focus
```

## Module Structure

```
lib/gtty/
  mod.nu            re-exports enter.nu, leave.nu, surface/
  enter.nu          gtty enter
  leave.nu          gtty leave
  completion.nu     shared completers: _panes, _actions, _signals, _ai, _readme
  surface/
    mod.nu          re-exports lib.nu, siblings.nu
    siblings.nu     gtty surface siblings
    lib.nu          tint/flash helpers and TINT_DIM / TINT_FLASH constants
```

## Tab Completion

All flags support `--<TAB>` completion. `--offset` queries Ghostty live and
shows sibling pane offsets with TTY device and foreground command:

```
--offset -1    ▶ kak           ttys021  pane 2: completion.nu - Kakoune
--offset +1    ▶ gitui         ttys025  pane 4: README.md - Kakoune
```

Results are cached in-memory (Nushell `stor`) with a 60-second TTL.

`--ai` completes the available AI providers:

```
agy       Antigravity CLI (Google)
claude    Claude Code (Anthropic)
gemini    Gemini CLI (Google)
pi        Pi (pi.dev)
```

## Requirements

- macOS with [Ghostty](https://ghostty.org/) installed
- Nushell ≥ 0.100

## Loading

The module is loaded via `scripts/init.nu`:

```nushell
use ./lib/gtty
```

## References

- https://ghostty.org/docs/features/applescript

> [!CAUTION]
> This file was generated with AI assistance (Claude Code).
