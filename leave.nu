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
    let bundle_id  = (ghostty_bundle_id)
    let info       = (my_index $bundle_id)
    let me         = $info.index
    let n          = $info.count

    if $n != 4 {
        error make { msg: $"Expected 4 panes, found ($n) — is this a workspace tab?" }
    }

    if not $force {
        let answer = (input "Close workspace siblings? [yes/no]: " | str trim | str downcase)
        if $answer != "yes" {
            print "Aborted."
            return
        }
    }

    let to_close = (1..$n | each { $in } | reverse | where { $in != $me })

    # Try the first close; a failure means the split is zoomed and the
    # AppleScript close API cannot reach the hidden panes. Unzoom and retry.
    let first = ($to_close | first)
    let rest  = ($to_close | skip 1)

    let ok = (try {
        ^osascript -e $"tell application id \"($bundle_id)\" to close terminal ($first) of selected tab of front window" out+err> /dev/null
        true
    } catch {
        false
    })

    # Unzoom the focused split so all panes become reachable, then close all.
    if not $ok {
        ^osascript -e $"tell application id \"($bundle_id)\" to perform action \"toggle_split_zoom\" on terminal ($me) of selected tab of front window" out+err> /dev/null
        for i in $to_close {
            ^osascript -e $"tell application id \"($bundle_id)\" to close terminal ($i) of selected tab of front window" out+err> /dev/null
        }

        focus_first_terminal $bundle_id
        return
    }

    # Close the rest of still running siblings
    for i in $rest {
        ^osascript -e $"tell application id \"($bundle_id)\" to close terminal ($i) of selected tab of front window"
    }

    focus_first_terminal $bundle_id
}

def focus_first_terminal [bundle_id: string] {
    ^osascript -e $"
        tell application id \"($bundle_id)\"
            focus terminal 1 of selected tab of front window
        end tell"
}
