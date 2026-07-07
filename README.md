# libgtty.nu

[Nushell](https://www.nushell.sh/) module designed to manage and orchestrate [Ghostty](https://ghostty.org/)
workspace surface layouts and pane interactions via the native [Ghostty AppleScript API](https://ghostty.org/docs/features/applescript).

## Features

- **Surface Sibling Interactions**: Focus, flash, tint, or gracefully terminate process trees on targeted sibling panes
- **Low-Latency Keyboard Broadcasting**: Mirror keystrokes and inputs to multiple sibling surfaces in real-time
- **Fuzzy Tab Completion**: Live terminal introspection with cached results (`stor` database with 60-second TTL)
- **Workspace Layout Orchestration**: Instantly build or tear down structured multi-surface layouts

---

## Requirements

> [!IMPORTANT]
> A currently unreleased version of Ghostty is required to support the AppleScript `send key` and `input text` APIs.
>
> - **Pending Upstream PR**: [ghostty-org/ghostty#13180](https://github.com/ghostty-org/ghostty/pull/13180)
> - **Required Fork**: [paaloeye/ghostty (feat/applescript-send-key-text-part-1)](https://github.com/paaloeye/ghostty/tree/feat/applescript-send-key-text-part-1)

- **Operating System**: **macOS** with **Ghostty** installed
- **Shell**: **Nushell** ≥ 0.114
- **Swift**: Toolchain ≥ 6.0 (required to build the low-latency broadcast engine)

---

## Installation & Setup

### 1. Compile Swift Broadcast Engine

The low-latency broadcast engine requires compilation before use:

```bash
cd surface/broadcast
swift build -c release
```

This compiles the executable binary `gtty-surface-broadcast` inside `surface/broadcast/.build/release/`.

### 2. Loading the Module

Add the following to your `config.nu`:

```nushell
use /path/to/libgtty
```

---

## Commands

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

<details>
<summary>See it in action!</summary>

https://github.com/user-attachments/assets/5e6c77cb-6067-4325-9ca6-250761755a11

</details>

---

### `gtty enter`

Builds a structured multi-surface workspace layout in the current tab.
The layout is dynamically configured from a local `.workspace.kdl` or `.workspace.default.kdl`
layout file (see [Workspace Layout Configuration](#workspace-layout-configuration) for customisation details).

```nushell
gtty enter [target_dir] [--file <path>] [--ai <provider>] [--ai-session <id>]
```

#### Default Visual Layout

```text
+-----------------------+------------------------------+
|                       |                              |
|   t1: nnn README.md   |  t3: nnn                     |
|                       |                              |
+-----------------------+------------------------------+
|                       |              |               |
|   t2: <ai>            |  t3: nnn     |  t5: gitui    |
|                       |              |               |
+-----------------------+------------------------------+
```

| Argument / Flag | Default      | Description                                                        |
| :-------------- | :----------- | :----------------------------------------------------------------- |
| `target_dir`    | Current Dir  | Target directory to enter and set as the initial working directory |
| `--file`        | First README | File to open in the editor (defaults to the first existing README) |
| `--ai`          | `agy`        | AI provider to launch in t2 (`agy`, `claude`, `gemini`, or `pi`)   |
| `--ai-session`  | `""`         | Session ID to resume with `--resume` (provider-agnostic)           |

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

Closes the sibling panes created by `gtty enter`. This command requires a multi-pane workspace in the current tab. The
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

## Workspace Layout Configuration

Workspace pane layouts are dynamically defined and compiled using [KDL](https://kdl.dev/) configuration files.
When executing `gtty enter`, the layout file is resolved in the following priority:

1. **Workspace Configuration**: `.workspace.kdl` in the workspace directory.
2. **Default Configuration**: Fallback to the `.workspace.default.kdl` file distributed with the `libgtty.nu` itself.

---

### KDL Layout Schema

A workspace layout configuration uses a structured `workspace` block containing hierarchical layout containers and surfaces.

#### Layout Nodes

- **`workspace` (Root)**: Represents the top-level container of the tab.
- **`box`**: Group of surfaces or nested splits layout container. Supports an optional `direction` attribute (`h` for horizontal or `v` for vertical, defaulting to `h`).
- **`split direction=<h|v>`**: Splits the current pane container or box in the specified direction.
- **`break direction=<h|v>`**: Splits within a layout box block.
- **`surface`**: Individual terminal pane representing a process or command.

#### Surface Properties

Inside a `surface` block, you can configure the target pane details:

- **`type`**: The role or predefined application command of the pane (`editor`, `fs` for file manager, `ai`, or `git`).
- **`command`**: Execute a custom shell command instead of predefined application types (e.g. `command "htop -d 10"`).
- **`argv`**: Arguments to pass to the predefined application (supported for `editor` and `fs` types).
- **`start_suspended`**: A boolean flag (`true`/`false`). If set to `true`, the layout compiler prevents sending the **Enter** key automatically to the target pane, keeping the command typed but unexecuted.

---

### Layout Examples

Below is a typical multi-pane workspace layout configuration utilising horizontal/vertical breaks and split structures:

```kdl
workspace {
    box direction=h {
        surface {
            type "editor"
            argv "README.md"
        }

        break direction=v

        surface {
            type "fs"
        }
    }

    split direction=h

    box {
        surface {
            type "ai"
            start_suspended true
        }

        break direction=v

        surface {
            type "fs"
        }

        split direction=v

        surface {
            type "git"
        }
    }
}
```

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

## Testing

The project utilises the [nutest](https://github.com/vyadh/nutest) testing framework for Nushell to maintain a
comprehensive and reliable suite of unit and integration tests.

### Running Tests Locally

To run the full test suite locally, use the provided Nushell test execution script:

```nushell
./scripts/run_tests.nu --fail
```

This script automates the entire test orchestration lifecycle:

1. Clones the correct version of the `nutest` framework into `vendor/nutest` if it is not already present.
2. Changes to the repository root directory to ensure reliable resolution of relative module and asset paths.
3. Spawns Nushell cleanly without loading user configurations (`--no-config-file`) to execute the test runner.

#### Options

The test script supports filtering and configuration options:

| Flag             | Type     | Description                                                           |
| :--------------- | :------- | :-------------------------------------------------------------------- |
| `path`           | `string` | Directory to discover tests in (defaults to `tests`).                 |
| `--match-suites` | `string` | Regular expression to match against suite names.                      |
| `--match-tests`  | `string` | Regular expression to match against test names.                       |
| `--fail`         | `switch` | Exit with a non-zero status code if any tests fail (ideal for CI/CD). |
| `--display`      | `string` | Display options during test execution (defaults to terminal).         |

---

### Test Coverage

The test suite covers key elements of the `libgtty.nu` architecture:

- **Core Behaviours (`tests/test_lib.nu`)**:
  - Validates that the active Nushell environment meets version requirements.
  - Verifies Ghostty application bundle identifier resolution and fallback behaviours under different environment states.
- **Tab Completions (`tests/test_completions.nu`)**:
  - Exercises static completers for actions, signal options, registered AI providers, and broadcast engines.
  - Seeds, queries, and asserts on the in-process SQLite cache lifecycle using Nushell's in-memory `stor` database.
- **Layout Compilations (`tests/test_compile_layout.nu`)**:
  - Compiles multiple KDL workspace definitions from `tests/fixtures/` and parses them into target-platform
    AppleScript commands.
  - Verifies compilation behaviour for horizontal and vertical splits, multi-pane grids, suspended surfaces, and
    custom command injection.

---

### Continuous Integration (CI)

A GitHub Actions workflow is defined at `.github/workflows/test.yml` to automatically verify every push and pull
request targeting the `main` branch.

The CI environment runs on a `macos-latest` runner and executes the following sequence:

1. Check out the repository.
2. Install and configure Nushell (pinned to `0.114.0`).
3. Clone and pin the `nutest` framework dependency (`v1.2.0`).
4. Build the high-performance Swift broadcasting engine inside `surface/broadcast`.
5. Run the Nushell test suite in fail-fast mode.

> [!NOTE]
> Tests that inspect Nushell's `stor` SQLite tables run synchronously within the same test context. This avoids
> database race conditions which can occur during parallel test runs.

---

## Area of active development

- [ ] Tint colour and change of colour scheme
- [x] KDL based layout workspace configuration

---

## References

- [Ghostty AppleScript Documentation](https://ghostty.org/docs/features/applescript)
- [KDL format support in Nushell](https://github.com/nushell/nushell/pull/18219)
- [KDL format spec](https://kdl.dev/spec/)

> [!CAUTION]
> This file was refined with AI assistance (Antigravity).
