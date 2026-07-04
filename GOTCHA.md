# GOTCHA.md

Common gotchas and pitfalls when working with **Agents** in AI-aided fashion.

This file provides guidance to **Agent** when it keeps making the same mistakes.

## 🤖 Command Substitution in Git Commit Messages (ai.nu)

### Issue

When attempting to include agent/tool info via `$(ai.nu ...)` in git commit messages, developers might accidentally escape the dollar sign (e.g. `\$(ai.nu ...)`).

### Symptoms

The generated commit message contains the literal text `$(ai.nu agent get-caller-identity)` instead of the evaluated agent name (e.g. `Antigravity CLI 1.0.16`).

### Example Problem

```bash
# ❌ Escaped dollar sign prevents evaluation
git commit -m "$(cat <<EOF
...
Co-Authored-By: \$(ai.nu agent get-caller-identity)
EOF
)"
```

### Solution

Do NOT escape the dollar sign (`$`). The `ai.nu` tool and script are fully whitelisted in the environment, so command substitutions like `$(ai.nu ...)` can be run unescaped in heredocs and string interpolation safely.

```bash
# ✅ Unescaped for correct shell evaluation
git commit -m "$(cat <<EOF
...
Co-Authored-By: $(ai.nu agent get-caller-identity)
EOF
)"
```

### Why This Happens

- Over-cautious escaping leads to escaping the `$` sign inside double-quoted heredocs.
- Unquoted heredocs (`cat <<EOF` instead of `cat <<'EOF'`) permit variable and command substitution. Escaping the `$` stops the shell from running the command, leaving the literal script text.

### Prevention

- Always leave `$(ai.nu ...)` unescaped when writing heredocs for git commits.
- Remember that `ai.nu` is fully whitelisted in the environment and doesn't require safety escapes.

## 🤖 Nushell: `ai.nu` is in the `PATH`, do not invoke via `nu -c` or local paths

### Issue

Invoking `ai.nu` with `nu -c "ai.nu agent get-caller-identity"` or relative paths like `nu scripts/ai.nu` is redundant, fails depending on current working directories,
or prompts for unneeded permissions when running in automated environments.

### Symptoms

Attempts to run command-line actions or queries using explicit interpreter invocations prompt for extra permissions or fail with file-not-found errors:

```text
Error: nu::shell::file_not_found
  × File not found
   Help: File 'scripts/ai.nu' not found
```

### Example Problem

```bash
# ❌ Redundant interpreter invocation and command execution string
nu -c "ai.nu agent get-caller-identity"

# ❌ Directory-dependent relative path
nu scripts/ai.nu agent get-caller-identity
```

### Solution

Run `ai.nu` directly as a global command from any directory inside the repository. The system `PATH` handles resolution automatically:

```bash
# ✅ Direct global invocation
ai.nu agent get-caller-identity
```

### Why This Happens

- The `ai.nu` script is globally added to the user's `PATH` and has a proper shebang (`#!/usr/bin/env nu`).
- Standard shells (like `zsh`) can execute it directly without wrapping it in a Nushell command-string (`nu -c`) or prepending a local path.
- Wrapping the call or hardcoding local paths is brittle and breaks when changing sub-project contexts.

### Prevention

Always refer to the helper tool as `ai.nu` directly. Do not use local directories or wrap it in a child shell invocation.
