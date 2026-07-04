# libgtty

[Nushell](https://www.nushell.sh/) module designed to manage and orchestrate [Ghostty](https://ghostty.org/)
workspace surface layouts and pane interactions via the native [Ghostty AppleScript API](https://ghostty.org/docs/features/applescript).

## Features

- **Workspace Layout Orchestration**: Instantly build or tear down structured 4-surface layouts.
- **Surface Sibling Interactions**: Focus, flash, tint, or gracefully terminate process trees on targeted sibling panes.
- **Low-Latency Keyboard Broadcasting**: Mirror keystrokes and inputs to multiple sibling surfaces in real-time.
- **Fuzzy Tab Completion**: Live terminal introspection with cached results (`stor` database with 60-second TTL).

---

## Requirements

> [!IMPORTANT]
> A currently unreleased version of Ghostty is required to support the AppleScript `send key` and `input text` APIs.
>
> - **Pending Upstream PR**: [ghostty-org/ghostty#13180](https://github.com/ghostty-org/ghostty/pull/13180)
> - **Required Fork**: [paaloeye/ghostty (feat/applescript-send-key-text-part-1)](https://github.com/paaloeye/ghostty/tree/feat/applescript-send-key-text-part-1)

- **Operating System**: macOS with Ghostty installed.
- **Shell**: Nushell ≥ 0.100.
- **Swift**: Toolchain ≥ 6.0 (required to build the high-performance broadcast engine).

---

## Installation & Setup

### 1. Compile the Swift Broadcast Engine

The high-performance broadcast engine requires compilation before use:

```bash
cd surface/broadcast
swift build -c release
```

This compiles the executable binary `gtty-surface-broadcast` inside `surface/broadcast/.build/release/`.

### 2. Loading the Module

Import `libgtty` into your Nushell session:

```nushell
use /path/to/libgtty
```

Alternatively, load it through `scripts/init.nu`:

```nushell
use ./lib/gtty
```

---

## Commands

### `gtty enter`

Builds a structured 4-surface workspace layout in the current tab.

```nushell
gtty enter [--file <path>] [--ai <provider>] [--ai-session <id>]
```

#### Visual Layout

```text
+-----------------------+-----------------------+
|                       |                       |
|   t1: editor <file>   |   t3: editor          |
|                       |                       |
+-----------------------+-----------------------+
|                       |                       |
|   t2: <ai>            |   t4: gitui           |
|                       |                       |
+-----------------------+-----------------------+
```

| Flag           | Default      | Description                                                        |
| :------------- | :----------- | :----------------------------------------------------------------- |
| `--file`       | First README | File to open in the editor (defaults to the first existing README) |
| `--ai`         | `agy`        | AI provider to launch in t2 (`agy`, `claude`, `gemini`, or `pi`)   |
| `--ai-session` | `""`         | Session ID to resume with `--resume` (provider-agnostic)           |

The AI binary is resolved from the environment:

| Provider | Environment Variable   | Default Binary |
| :------- | :--------------------- | :------------- |
| `agy`    | `$env.ANTIGRAVITY_CLI` | `ag`           |
| `claude` | `$env.CLAUDE`          | `cl`           |
| `gemini` | `$env.GEMINI`          | `gi`           |
| `pi`     | `$env.PI`              | `pi`           |

> [!NOTE]
> The workspace layout launches the command configured in `$env.EDITOR` inside terminal 1 and terminal 3. If `$env.EDITOR` is not defined, it defaults to [`nnn`](https://github.com/jarun/nnn) (the terminal file manager).

> [!NOTE]
> The AI command is typed into terminal 2 but **not automatically sent**.

---

### `gtty leave`

Closes the 3 sibling panes created by `gtty enter`. This command requires exactly 4 panes in the current tab. The
tab itself remains open.

```nushell
gtty leave [--force]
```

| Flag      | Description                              |
| :-------- | :--------------------------------------- |
| `--force` | Skip the interactive confirmation prompt |

> [!TIP]
> If the focused pane is currently zoomed (`cmd+shift+enter`), it will be automatically unzoomed before closing siblings
> so that all panes remain accessible via AppleScript.

---

### `gtty surface siblings`

Perform a one-shot or looping action on a sibling pane by relative offset.

```nushell
gtty surface siblings --offset <offset> --action <action> [options]
```

| Flag         | Default    | Description                                                |
| :----------- | :--------- | :--------------------------------------------------------- |
| `--offset`   | _Required_ | Relative offset from the focused pane (e.g. `+1`, `-1`)    |
| `--action`   | _Required_ | Action to perform (`kill`, `auto-accept`, or `focus`)      |
| `--args`     | `""`       | Key-value pairs (e.g. `signal=term,confirm=true`)          |
| `--max`      | `1984`     | Maximum command sends (`auto-accept` action only)          |
| `--interval` | `5sec`     | Duration between command sends (`auto-accept` action only) |

#### Available Actions

- **`kill`**: Send a signal to all processes attached to the target pane's TTY.
  ```nushell
  gtty surface siblings --offset +1 --action kill
  gtty surface siblings --offset +1 --action kill --args signal=hup,confirm=false
  ```
- **`auto-accept`**: Repeatedly send **Enter** to an agent surface to auto-accept prompts. Tints the target pane dark red
  (`#1c1214`) while active. Terminate with `Ctrl+C`.
  ```nushell
  gtty surface siblings --offset -1 --action auto-accept
  gtty surface siblings --offset -1 --action auto-accept --max 10 --interval 10sec
  ```
- **`focus`**: Move keyboard focus to the target pane with a brief visual flash confirmation.
  ```nushell
  gtty surface siblings --offset +1 --action focus
  ```

---

### `gtty surface broadcast`

Broadcast keyboard input in real-time to one or more sibling Ghostty surfaces.

```nushell
gtty surface broadcast --offset <offset> [--engine <engine>]
```

| Flag       | Default    | Description                                            |
| :--------- | :--------- | :----------------------------------------------------- |
| `--offset` | _Required_ | Relative surface offset(s) (e.g. `+1`, `-1`, `-2..+1`) |
| `--engine` | `swift`    | The underlying execution engine (`swift` or `nu`)      |

#### Broadcast Engines

- **`swift` (Default)**: High-performance, compiled binary written in Swift. It enters terminal raw mode, parses ANSI escape
  sequences into structured key events, and uses high-speed NSAppleScript events to type into target panes. Highly
  recommended for complex/fast typing.
- **`nu`**: A pure Nushell fallback implementation using Nushell's native `input listen` loop.

---

## Tab Completion

All flags support native `--<TAB>` completion. The `--offset` flag queries Ghostty live and presents sibling pane
offsets alongside their active TTY device and running foreground commands:

```text
--offset -1    ▶ kak           ttys021  pane 2: completion.nu - Kakoune
--offset +1    ▶ gitui         ttys025  pane 4: README.md - Kakoune
```

Live completions are cached in-memory using Nushell's `stor` database with a 60-second TTL to keep interactions
highly responsive.

`--ai` completions list all registered AI providers:

```text
agy       Antigravity CLI (Google)
claude    Claude Code (Anthropic)
gemini    Gemini CLI (Google)
pi        Pi (pi.dev)
```

---

## Module Structure

```text
lib/gtty/
  mod.nu            — re-exports enter.nu, leave.nu, and surface/
  enter.nu          — gtty enter implementation
  leave.nu          — gtty leave implementation
  completion.nu     — shared tab completers: _panes, _actions, _signals, _ai, _readme
  surface/
    mod.nu          — re-exports lib.nu, siblings.nu, and broadcast.nu
    siblings.nu     — gtty surface siblings implementation
    broadcast.nu    — gtty surface broadcast implementation
    lib.nu          — tint/flash helpers and TINT_DIM / TINT_FLASH colour constants
    broadcast/      — Swift broadcast engine package
```

---

## References

- [Ghostty AppleScript Documentation](https://ghostty.org/docs/features/applescript)

> [!CAUTION]
> This file was refined with AI assistance (Antigravity).
