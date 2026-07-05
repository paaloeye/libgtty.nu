#
#  SPDX-License-Identifier: MIT
#  Copyright (c) 2026 Paal Øye-Strømme
#
#  lib.nu
#  libgtty.nu
#

# Walk the process tree to find the nearest macOS app bundle ancestor and return its CFBundleIdentifier.
export def ghostty_bundle_id [] {
    if "__CFBundleIdentifier" in $env {
        return $env.__CFBundleIdentifier
    }

    mut pid = $nu.pid
    loop {
        let ppid_str = (^ps -p $pid -o ppid= | str trim)
        if ($ppid_str | is-empty) { break }
        let ppid = ($ppid_str | into int)
        if $ppid <= 1 { break }

        let cf_bundle_entry = (^ps -p $ppid -E
            | lines
            | skip 1
            | get 0?
            | default ""
            | split row ' '
            | where { $in | str starts-with '__CFBundleIdentifier=' }
            | get 0?)

        if $cf_bundle_entry != null {
            return ($cf_bundle_entry | split row '=' | get 1)
        }

        $pid = $ppid
    }

    # Safe default fallback for Ghostty
    "com.mitchellh.ghostty"
}

export def my_index [bundle_id: string] {
    let info = (^osascript -e $"
        tell application id \"($bundle_id)\"
            set n to count terminals of selected tab of front window
            set fid to id of focused terminal of selected tab of front window
            repeat with i from 1 to n
                if id of terminal i of selected tab of front window is fid then return \(i as text\) & \":\" & \(n as text\)
            end repeat
        end tell" | str trim | split row ":")
    { index: ($info.0 | into int), count: ($info.1 | into int) }
}
