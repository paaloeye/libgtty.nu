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

    let bundle_id  = (ghostty_bundle_id)

    # Get all terminal IDs and the focused terminal's ID to prevent index shifting bugs during closure
    let terminal_ids = (^osascript -e $"tell application id \"($bundle_id)\" to get id of every terminal of selected tab of front window" | str trim | split row ", ")
    let focused_id   = (^osascript -e $"tell application id \"($bundle_id)\" to get id of focused terminal of selected tab of front window" | str trim)
    let n            = ($terminal_ids | length)

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
            ^osascript -e $"tell application id \"($bundle_id)\" to close \(first terminal of selected tab of front window whose id is \"($tid)\"\)" out+err> /dev/null
            true
        } catch {
            false
        })

        if not $ok {
            # Unzoom the focused split and retry closing the target terminal
            ^osascript -e $"tell application id \"($bundle_id)\" to perform action \"toggle_split_zoom\" on focused terminal of selected tab of front window" out+err> /dev/null
            ^osascript -e $"tell application id \"($bundle_id)\" to close \(first terminal of selected tab of front window whose id is \"($tid)\"\)"
        }
    }

    focus_first_terminal $bundle_id
}

def focus_first_terminal [bundle_id: string] {
    ^osascript -e $"
        tell application id \"($bundle_id)\"
            focus terminal 1 of selected tab of front window
        end tell"
}
