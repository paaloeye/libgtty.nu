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

# Get the TTY device path for the current process.
export def current_tty [] {
    if ($env.TTY? | default "" | is-not-empty) {
        return $env.TTY
    }

    let from_tty = try { ^tty | str trim } catch { "" }
    if ($from_tty | is-not-empty) and ($from_tty != "not a tty") {
        return $from_tty
    }

    let from_ps = try { ^ps -p $nu.pid -o tty= | str trim } catch { "" }
    if ($from_ps | is-not-empty) and ($from_ps != "?") {
        if ($from_ps | str starts-with "/") {
            return $from_ps
        } else {
            return $"/dev/($from_ps)"
        }
    }

    ""
}

export def my_index [bundle_id: string] {
    let my_tty = (current_tty)
    let raw = (try {
        ^osascript -e $"
        tell application id \"($bundle_id)\"
            set my_tty to \"($my_tty)\"
            set found_win to \"\"
            set found_tab to \"\"
            set found_tab_idx to 0
            set my_term_idx to 0
            set my_term_id to \"\"
            set term_count to 0

            if my_tty is not \"\" then
                set winList to every window
                repeat with w in winList
                    set tabList to every tab of w
                    repeat with tb in tabList
                        set trmList to every terminal of tb
                        repeat with i from 1 to \(count of trmList\)
                            set trm to item i of trmList
                            set pane_tty to \"\"
                            try
                                set pane_tty to tty of trm
                            end try
                            if pane_tty is my_tty then
                                set found_win to id of w
                                set found_tab to id of tb
                                set found_tab_idx to index of tb
                                set my_term_idx to i
                                set my_term_id to id of trm
                                set term_count to count of trmList
                                exit repeat
                            end if
                        end repeat
                        if my_term_id is not \"\" then exit repeat
                    end repeat
                    if my_term_id is not \"\" then exit repeat
                end repeat
            end if

            if my_term_id is \"\" then
                try
                    set found_win to id of front window
                    set found_tab to id of selected tab of front window
                    set found_tab_idx to index of selected tab of front window
                    set my_term_id to id of focused terminal of selected tab of front window
                    set term_count to count of terminals of selected tab of front window
                    repeat with i from 1 to term_count
                        if id of terminal i of selected tab of front window is my_term_id then
                            set my_term_idx to i
                            exit repeat
                        end if
                    end repeat
                end try
            end if

            return found_win \u{26} \":\" \u{26} found_tab \u{26} \":\" \u{26} \(found_tab_idx as text\) \u{26} \":\" \u{26} \(my_term_idx as text\) \u{26} \":\" \u{26} my_term_id \u{26} \":\" \u{26} \(term_count as text\)
        end tell"
    } catch { "" } | str trim)

    let parts = ($raw | split row ":")
    if ($parts | length) >= 6 {
        {
            win_id: ($parts | get 0),
            tab_id: ($parts | get 1),
            tab_idx: (try { $parts | get 2 | into int } catch { 1 }),
            index: (try { $parts | get 3 | into int } catch { 1 }),
            term_id: ($parts | get 4),
            count: (try { $parts | get 5 | into int } catch { 1 }),
        }
    } else {
        { win_id: "", tab_id: "", tab_idx: 1, index: 1, term_id: "", count: 1 }
    }
}

# Ensure the current Nushell version is 0.114.0 or higher.
export def ensure_nu_version [] {
    let ver = (version)
    let is_valid = (($ver.major > 0) or ($ver.major == 0 and $ver.minor >= 114))
    if not $is_valid {
        error make {
            msg: $"Nushell version ($ver.version) is not supported. Nushell 0.114.0 or higher is required."
        }
    }
}
