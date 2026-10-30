#
#  SPDX-License-Identifier: MIT
#  Copyright (c) 2026 Paal Øye-Strømme
#
#  leave.nu
#  libgtty.nu
#

use lib.nu *

# Close sibling surfaces of the workspace created by `gtty enter`.
#
# Requires exactly 4 panes in the current tab. The tab itself is not closed.
# If the focused pane is zoomed (cmd+shift+enter), it is unzoomed first so
# the Ghostty AppleScript close calls succeed.
#
export def main [
    --force (-f)                  # skip confirmation prompt
    --title: string = ""          # tab title override on leave (default: "" clears override)
    --keep-title                  # preserve existing tab and terminal title overrides
] {
    ensure_nu_version

    let bundle_id = (ghostty_bundle_id)
    let info      = (my_index $bundle_id)

    # Get all terminal IDs and the focused terminal's ID to prevent index shifting bugs during closure
    let terminal_ids = if not ($info.win_id | is-empty) and not ($info.tab_id | is-empty) {
        try {
            ^osascript -e $"
            tell application id \"($bundle_id)\"
                set w to first window whose id is \"($info.win_id)\"
                set tb to first tab of w whose id is \"($info.tab_id)\"
                return id of every terminal of tb
            end tell" | str trim | split row ", "
        } catch { [] }
    } else {
        try {
            ^osascript -e $"tell application id \"($bundle_id)\" to get id of every terminal of selected tab of front window" | str trim | split row ", "
        } catch { [] }
    }

    let focused_id = if not ($info.term_id | is-empty) {
        $info.term_id
    } else {
        (^osascript -e $"tell application id \"($bundle_id)\" to get id of focused terminal of selected tab of front window" | str trim)
    }

    let n = ($terminal_ids | length)

    if $n <= 1 {
        error make { msg: "No siblings found — this does not appear to be a multi-pane workspace tab" }
    }

    if not $force {
        let answer = (input "Close workspace siblings? [yes/no]: " | str trim | str lowercase)
        if $answer != "yes" {
            print "Aborted."
            return
        }
    }

    let to_close = ($terminal_ids | where { $in != $focused_id })
    let to_close_as_list = ($to_close | each { |id| $"\"($id)\"" } | str join ", ")

    let title_script = if not $keep_title {
        $"
        try
            set title override of tb to \"($title)\"
        end try
        if foc_trm is not missing value then
            try
                set title override of foc_trm to \"\"
            end try
        end if"
    } else {
        ""
    }

    let script = $"
    tell application id \"($bundle_id)\"
        set tb to missing value
        if \"($info.win_id)\" is not \"\" and \"($info.tab_id)\" is not \"\" then
            try
                set w to \(first window whose id is \"($info.win_id)\"\)
                set tb to \(first tab of w whose id is \"($info.tab_id)\"\)
            end try
        end if
        if tb is missing value then
            set tb to selected tab of front window
        end if

        set foc_trm to missing value
        if \"($focused_id)\" is not \"\" then
            try
                set foc_trm to \(first terminal of tb whose id is \"($focused_id)\"\)
            end try
        end if
        if foc_trm is missing value then
            try
                set foc_trm to focused terminal of tb
            end try
        end if

        repeat with tid in {($to_close_as_list)}
            set trm_id to \(tid as text\)
            try
                set trm to \(first terminal of tb whose id is trm_id\)
                close trm
            on error
                if foc_trm is not missing value then
                    try
                        perform action \"toggle_split_zoom\" on foc_trm
                    end try
                end if
                try
                    set trm to \(first terminal of tb whose id is trm_id\)
                    close trm
                end try
            end try
        end repeat

        if foc_trm is not missing value then
            try
                focus foc_trm
            end try
        end if

        ($title_script)
    end tell"

    ^osascript -e $script
}
