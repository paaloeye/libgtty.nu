#
#  SPDX-License-Identifier: MIT
#  Copyright (c) 2026 Paal Øye-Strømme
#
#  enter.nu
#  libgtty.nu
#

use completion.nu *
use lib.nu *

# Build a workspace layout in the current Ghostty tab (4-pane layout).
#
# Tab layout:
#   [t1: nnn <readme>]                [t3: nnn]
#   [t2: $env.CLAUDE | $env.GEMINI]   [t4: gitui]
#
export def main [
    --file: string@_readme = ""    # file to open in $env.EDITOR (default: first existing README)
    --ai: string@_ai = "agy"       # AI to be used (default: agy)
    --ai-session: string = ""      # AI session ID to resume (default: nil)
] {
    let bundle_id  = (ghostty_bundle_id)
    let pane_count = (^osascript -e $"
        tell application id \"($bundle_id)\"
            return count terminals of selected tab of front window
        end tell" | str trim | into int)

    if $pane_count > 1 {
        error make { msg: $"Tab already has ($pane_count) panes — workspace must start from a single pane" }
    }

    let cwd    = $env.PWD
    let editor = ($env.EDITOR? | default "nnn")

    # TODO: make it your own
    # let aurum_bin       = ($env.AURUM?          | default "au") # 🥇

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

    let editor_cmd = $"($editor) ($resolved_file)"

    ^osascript -e $"
tell application id \"($bundle_id)\"
    set cwd to \"($cwd)\"
    set t1 to terminal 1 of selected tab of front window

    -- bottom-left: antigravity-cli
    set cfg2 to new surface configuration
    set initial working directory of cfg2 to cwd
    set t2 to split t1 direction down with configuration cfg2

    -- top-right: zzz
    set cfg3 to new surface configuration
    set initial working directory of cfg3 to cwd
    set t3 to split t1 direction right with configuration cfg3

    -- bottom-right: gitui
    set cfg4 to new surface configuration
    set initial working directory of cfg4 to cwd
    set t4 to split t2 direction right with configuration cfg4

    input text \"($editor_cmd)\" to t1
    send key \"enter\" to t1

    input text \"($ai_cmd)\" to t2
    -- do NOT start AI yet
    -- TODO: make sure HUMAN maximises the surface before starting AI
    -- send key \"enter\" to t2

    input text \"($editor)\" to t3
    send key \"enter\" to t3

    input text \"gitui\" to t4
    send key \"enter\" to t4

    focus t1
end tell"
}
