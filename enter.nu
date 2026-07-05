#
#  SPDX-License-Identifier: MIT
#  Copyright (c) 2026 Paal Øye-Strømme
#
#  enter.nu
#  libgtty.nu
#

use completion.nu *
use lib.nu *

# Build a workspace layout in the current Ghostty tab based on .workspace.kdl.
#
# Tab layout is dynamically defined by the KDL configuration file.
#
export def main [
    target_dir: string = ""        # Target directory to enter (default: current directory)
    --file: string@_readme = ""    # file to open in $env.EDITOR (default: first existing README)
    --ai: string@_ai = "agy"       # AI to be used (default: agy)
    --ai-session: string = ""      # AI session ID to resume (default: nil)
] {
    ensure_nu_version

    let bundle_id  = (ghostty_bundle_id)
    let pane_count = (^osascript -e $"
        tell application id \"($bundle_id)\"
            return count terminals of selected tab of front window
        end tell" | str trim | into int)

    if $pane_count > 1 {
        error make { msg: $"Tab already has ($pane_count) panes — workspace must start from a single pane" }
    }

    let cwd = if ($target_dir | is-empty) { $env.PWD } else { $target_dir | path expand }
    let editor_cmd = ($env.EDITOR? | default $env.VISUAL? | default "vi")
    let fs_cmd     = ($env.NNN? | default "nnn")

    let claude_bin          = ($env.CLAUDE?          | default "cl") # Cl₂
    let gemini_bin          = ($env.GEMINI?          | default "gi")
    let antigravity_cli_bin = ($env.ANTIGRAVITY_CLI? | default "ag") # 🥈 or 🜛
    let pi_bin              = ($env.PI?              | default "pi")

    let ai_bin = match ($ai) {
        "claude" => $claude_bin,
        "gemini" => $gemini_bin,
        "agy" => $antigravity_cli_bin,
        "pi" => $pi_bin,
        _ => {
            error make { msg: $"Unsupported AI provider: '($ai)'." }
        }
    }

    let resolved_file = if not ($file | is-empty) {
        $file
    } else {
        let candidates = ["README.md" "README.adoc" "README.asciidoc"]
        let found = ($candidates | where { ($cwd | path join $in) | path exists } | get 0?)
        $found | default "README.md"
    }

    let ai_cmd = if ($ai_session | is-empty) {
        $ai_bin
    } else {
        $"($ai_bin) --resume ($ai_session)"
    }

    # Find layout KDL file
    let kdl_path = if (($cwd | path join ".workspace.kdl") | path exists) {
        $cwd | path join ".workspace.kdl"
    } else if (($cwd | path join ".workspace.default.kdl") | path exists) {
        $cwd | path join ".workspace.default.kdl"
    } else {
        const module_dir = (path self | path expand | path dirname)
        let package_default = ($module_dir | path join ".workspace.default.kdl")
        if ($package_default | path exists) {
            $package_default
        } else {
            error make { msg: "Could not find any workspace layout configuration (.workspace.kdl or .workspace.default.kdl)" }
        }
    }

    let applescript = (compile_layout $kdl_path $editor_cmd $fs_cmd $ai_cmd $cwd $resolved_file $bundle_id)

    ^osascript -e $applescript
}

def compile_layout [
    kdl_path: string
    editor_cmd: string
    fs_cmd: string
    ai_cmd: string
    cwd: string
    resolved_file: string
    bundle_id: string
] {
    let kdl_content = (open --raw $kdl_path | str replace -a " true" " #true" | str replace -a " false" " #false")
    let parsed = ($kdl_content | from kdl)

    if ($parsed | is-empty) or ($parsed | get 0 | get name) != "workspace" {
        error make { msg: "Invalid workspace KDL configuration: root node must be 'workspace'" }
    }
    let workspace = ($parsed | get 0)
    let children = $workspace.children
    let boxes = ($children | where name == "box")
    let grid_rows = ($boxes | each { |b|
        if $b.children == null { [] } else { $b.children | where name == "surface" }
    } | where { not ($in | is-empty) })

    if ($grid_rows | is-empty) {
        error make { msg: "No surfaces found in workspace KDL file" }
    }

    mut lines = [
        $"tell application id \"($bundle_id)\""
        $"    set cwd to \"($cwd)\""
        $"    set t0_0 to terminal 1 of selected tab of front window"
    ]
    mut terminal_vars = { "0_0": "t0_0" }

    let R = ($grid_rows | length)

    # Row 0 splits (horizontal splits going right)
    let C_0 = ($grid_rows | get 0 | length)
    for c in 1..<$C_0 {
        let prev_var = ($terminal_vars | get $"0_($c - 1)")
        let var_name = $"t0_($c)"
        $terminal_vars = ($terminal_vars | upsert $"0_($c)" $var_name)
        $lines = ($lines | append [
            $"    set cfg0_($c) to new surface configuration"
            $"    set initial working directory of cfg0_($c) to cwd"
            $"    set ($var_name) to split ($prev_var) direction right with configuration cfg0_($c)"
        ])
    }

    # Row 1..R splits
    for r in 1..<$R {
        let C_prev = ($grid_rows | get ($r - 1) | length)
        let C_curr = ($grid_rows | get $r | length)
        let min_c = (if $C_prev < $C_curr { $C_prev } else { $C_curr })

        for c in 0..<$min_c {
            let prev_var = ($terminal_vars | get $"($r - 1)_($c)")
            let var_name = $"t($r)_($c)"
            $terminal_vars = ($terminal_vars | upsert $"($r)_($c)" $var_name)
            $lines = ($lines | append [
                $"    set cfg($r)_($c) to new surface configuration"
                $"    set initial working directory of cfg($r)_($c) to cwd"
                $"    set ($var_name) to split ($prev_var) direction down with configuration cfg($r)_($c)"
            ])
        }

        if $C_curr > $C_prev {
            for c in $C_prev..<$C_curr {
                let prev_var = ($terminal_vars | get $"($r)_($c - 1)")
                let var_name = $"t($r)_($c)"
                $terminal_vars = ($terminal_vars | upsert $"($r)_($c)" $var_name)
                $lines = ($lines | append [
                    $"    set cfg($r)_($c) to new surface configuration"
                    $"    set initial working directory of cfg($r)_($c) to cwd"
                    $"    set ($var_name) to split ($prev_var) direction right with configuration cfg($r)_($c)"
                ])
            }
        }
    }

    # Apply surface configurations
    for r in 0..<$R {
        let row_surfaces = ($grid_rows | get $r)
        let C_curr = ($row_surfaces | length)
        for c in 0..<$C_curr {
            let surface = ($row_surfaces | get $c)
            let var_name = ($terminal_vars | get $"($r)_($c)")

            mut s_type = ""
            mut s_cmd = ""
            mut s_argv = []
            mut s_start_suspended = false

            if ($surface.children != null) {
                for attr in $surface.children {
                    let args = ($attr.args? | default [])
                    match $attr.name {
                        "type" => {
                            if ($args | length) > 0 {
                                $s_type = ($args | get 0)
                            }
                        }
                        "command" => {
                            if ($args | length) > 0 {
                                $s_cmd = ($args | get 0)
                            }
                        }
                        "argv" => {
                            $s_argv = $args
                        }
                        "start_suspended" => {
                            if ($args | length) > 0 {
                                $s_start_suspended = ($args | get 0)
                            }
                        }
                        _ => {}
                    }
                }
            }

            # Compile command string
            mut cmd_str = "clear"
            if $s_type == "editor" or $s_cmd == "editor" {
                if ($s_argv | length) > 0 {
                    let argv_str = ($s_argv | each { |a| if ($a | str contains " ") { $"\"($a)\"" } else { $a } } | str join " ")
                    $cmd_str = $"($editor_cmd) ($argv_str)"
                } else if $r == 0 and $c == 0 {
                    $cmd_str = $"($editor_cmd) ($resolved_file)"
                } else {
                    $cmd_str = $editor_cmd
                }
            } else if $s_type == "fs" or $s_cmd == "fs" {
                if ($s_argv | length) > 0 {
                    let argv_str = ($s_argv | each { |a| if ($a | str contains " ") { $"\"($a)\"" } else { $a } } | str join " ")
                    $cmd_str = $"($fs_cmd) ($argv_str)"
                } else {
                    $cmd_str = $fs_cmd
                }
            } else if $s_type == "ai" {
                $cmd_str = $ai_cmd
            } else if $s_type == "git" or $s_cmd == "git" {
                $cmd_str = "gitui"
            } else if not ($s_cmd | is-empty) {
                $cmd_str = $s_cmd
            }

            $lines = ($lines | append $"    input text \"($cmd_str)\" to ($var_name)")
            if not $s_start_suspended {
                $lines = ($lines | append $"    send key \"enter\" to ($var_name)")
            }
        }
    }

    $lines = ($lines | append [
        "    focus t0_0"
        "end tell"
    ])

    $lines | str join "\n"
}
