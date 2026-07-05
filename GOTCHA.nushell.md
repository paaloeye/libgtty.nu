# Nushell Gotchas and Learnings

A reference guide documenting crucial Nushell behaviours, command deprecations, and path-resolution subtleties encountered during the development of `libgtty`.

---

## 🤖 Environment Context

This document and the associated integrations were formulated under the following environment:

- **Nushell Version**: `0.114.0`
- **AI Agent**: `Antigravity CLI 1.0.16`
- **Model**: `Google Gemini 3.1 Pro (High)`

---

## 1. Deprecated String Command Transformations

Starting in Nushell version `0.114.0`, standard string casing commands have been deprecated and will be removed in subsequent versions.

### Symptoms

When executing scripts utilising the old string methods, Nushell outputs a `nu::parser::deprecated` warning:

```text
Warning: nu::parser::deprecated
  ⚠ Command deprecated.
  help: Use `str lowercase` / `str uppercase` instead.
```

### Gotchas

- **Do NOT use**: `str downcase` or `str upcase`.
- **Do use**: `str lowercase` and `str uppercase` instead.

---

## 2. Compile-Time vs Run-Time Path Resolution under Symbolic Links

When working with symbolic links (e.g., when the module directory is symlinked elsewhere, such as `~/Documents/GitHub/workspace/scripts/lib/gtty`
pointing to `~/Documents/GitHub/workspace/tools/libgtty.nu`), locating bundled resource files can be brittle.

### Issue

At run-time inside a function body, `$env.FILE_PWD` can be shadowed, evaluate to the caller's current working directory, or refer to temporary cached paths.
It does not consistently evaluate to the directory of the file containing the function definition.

Additionally, standard relative file paths do not resolve symbolic links automatically.

### Solution

Leverage parse-time constants (`const`) and canonicalisation (`path expand`):

- `path self` is a special Nushell construct evaluated at parse-time. It returns the absolute path of the file in which it is written.
- `path expand` canonicalises the path, fully resolving any symbolic links to their physical file targets.
- Defining a module-level or function-scoped `const` locks in the correct, physical path of the module at compilation time.

```nushell
# Correctly resolve the physical directory of this script, even if accessed via a symlink
const module_dir = (path self | path expand | path dirname)
let package_default = ($module_dir | path join ".workspace.default.kdl")
```

---

## 3. Native KDL Parsing and Boolean Handling

Nushell supports reading KDL configuration files directly via the built-in `from kdl` command.
This completely removes the need for external parsing or compiler scripts (e.g., Python scripts).

### Gotchas with Booleans

In standard KDL syntax, boolean values are represented as `true` or `false`.
However, depending on the KDL specification version and the parser's behaviour under Nushell,
unadorned boolean tokens may fail to parse or be parsed as unquoted strings instead of actual boolean types.

### Solution

In KDL, boolean nodes can be safely prefixed with `#` (e.g., `#true`, `#false`) to be parsed as native boolean values.

If loading raw KDL files that may contain standard unprefixed booleans, pre-process the string content to convert them to `#true`/`#false`
before passing the content to `from kdl`:

```nushell
let kdl_content = (open --raw $kdl_path
    | str replace -a " true" " #true"
    | str replace -a " false" " #false")
let parsed = ($kdl_content | from kdl)
```

---

## 4. Deprecated `get -i` Flag

When extracting data from structures like lists, tables, or records using cell paths, making cell paths optional is a common requirement to prevent errors on missing fields.

### Gotchas

- In older versions of Nushell, the `-i` / `--ignore-errors` flag was used with `get` to ignore missing data and make cell paths optional.
- **`get -i` is now deprecated** and will be removed in a future release.

### Solution

- **Use `-o` / `--optional` instead of `-i`**.
- Alternatively, use the optional cell path suffix syntax `?` (e.g., `$table | get field?` instead of `$table | get -i field`).

```nushell
# ❌ Deprecated
$record | get -i optional_field

# ✅ Standard
$record | get -o optional_field

# ✅ Alternative (cell path suffix)
$record | get optional_field?
```

---

> [!CAUTION]
> This file was compiled and written with AI assistance (Antigravity).
