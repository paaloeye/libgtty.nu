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
    --force (-f)  # skip confirmation prompt
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

    for tid in $to_close {
        let ok = (try {
            ^osascript -e $"tell application id \"($bundle_id)\" to close \(first terminal whose id is \"($tid)\"\)" out+err> /dev/null
            true
        } catch {
            false
        })

        if not $ok {
            # Unzoom the focused split and retry closing the target terminal
            if not ($focused_id | is-empty) {
                ^osascript -e $"tell application id \"($bundle_id)\" to perform action \"toggle_split_zoom\" on \(first terminal whose id is \"($focused_id)\"\)" out+err> /dev/null
            } else {
                ^osascript -e $"tell application id \"($bundle_id)\" to perform action \"toggle_split_zoom\" on focused terminal of selected tab of front window" out+err> /dev/null
            }
            ^osascript -e $"tell application id \"($bundle_id)\" to close \(first terminal whose id is \"($tid)\"\)"
        }
    }

    focus_terminal $bundle_id $focused_id
}

def focus_terminal [bundle_id: string, term_id: string] {
    if not ($term_id | is-empty) {
        ^osascript -e $"
            tell application id \"($bundle_id)\"
                focus \(first terminal whose id is \"($term_id)\"\)
            end tell"
    } else {
        ^osascript -e $"
            tell application id \"($bundle_id)\"
                focus terminal 1 of selected tab of front window
            end tell"
    }
}
