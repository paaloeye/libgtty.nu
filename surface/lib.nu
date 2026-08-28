#
#  SPDX-License-Identifier: MIT
#  Copyright (c) 2026 Paal Øye-Strømme
#
#  lib.nu
#  libgtty.nu
#

export use ../lib.nu [ ghostty_bundle_id my_index ensure_nu_version ]

export const TINT_DIM   = "#1c1214"
export const TINT_FLASH = "#2a1015"

export def tint [tty_dev: string, colour: string = $TINT_DIM] {
    if ($tty_dev | is-empty) { return }
    try {
        if ($colour | is-empty) {
            ^bash -c $"printf '\\e]111\\a' > ($tty_dev)"
        } else {
            ^bash -c $"printf '\\e]11;($colour)\\a' > ($tty_dev)"
        }
    } catch { }
}

export def flash [tty_dev: string, duration: duration = 300ms] {
    if ($tty_dev | is-empty) { return }
    tint $tty_dev $TINT_FLASH
    sleep $duration
    tint $tty_dev ""
}

export def focus [bundle_id: string, target: any] {
    let term_id = if ($target | describe | str starts-with "record") {
        $target.term_id? | default ""
    } else if ($target | describe | str starts-with "string") {
        $target
    } else {
        ""
    }

    try {
        if not ($term_id | is-empty) {
            ^osascript -e $"
                tell application id \"($bundle_id)\"
                    focus \(first terminal whose id is \"($term_id)\"\)
                end tell"
        } else {
            let idx = if ($target | describe | str starts-with "record") { $target.index } else { $target }
            ^osascript -e $"
                tell application id \"($bundle_id)\"
                    focus terminal ($idx) of selected tab of front window
                end tell"
        }
    } catch { }
}

export def find_tty_for_target [bundle_id: string, index: int, info?: record] {
    let resolved = if ($info != null) and not ($info.win_id | default "" | is-empty) and not ($info.tab_id | default "" | is-empty) {
        try {
            ^osascript -e $"
            tell application id \"($bundle_id)\"
                set w to first window whose id is \"($info.win_id)\"
                set tb to first tab of w whose id is \"($info.tab_id)\"
                return tty of terminal ($index) of tb
            end tell" e> /dev/null | str trim
        } catch { "" }
    } else {
        try {
            ^osascript -e $"tell application id \"($bundle_id)\" to get tty of terminal ($index) of selected tab of front window" e> /dev/null
                | str trim
        } catch { "" }
    }

    if not ($resolved | is-empty) {
        return $resolved
    }

    let win_tab = if ($info != null) and not ($info.win_id | default "" | is-empty) {
        $"($info.win_id):($info.tab_idx)"
    } else {
        (^osascript -e $"
            tell application id \"($bundle_id)\"
                return \(id of front window as text\) & \":\" & \(index of selected tab of front window as text\)
            end tell" | str trim)
    }

    let registry_path = ([$env.XDG_RUNTIME_DIR?, $env.TMPDIR?, "/tmp"]
        | compact
        | each { |d| [$d "ghostty_panes" $"($win_tab):($index)"] | path join }
        | where { |p| $p | path exists }
        | get 0?)

    if $registry_path == null {
        let name = if ($info != null) and not ($info.win_id | default "" | is-empty) and not ($info.tab_id | default "" | is-empty) {
            try {
                ^osascript -e $"
                tell application id \"($bundle_id)\"
                    set w to first window whose id is \"($info.win_id)\"
                    set tb to first tab of w whose id is \"($info.tab_id)\"
                    return name of terminal ($index) of tb
                end tell" | str trim
            } catch { $"terminal ($index)" }
        } else {
            ^osascript -e $"tell application id \"($bundle_id)\" to get name of terminal ($index) of selected tab of front window"
                | str trim
        }
        error make { msg: $"Cannot determine TTY for terminal ($index) \(($name)\)" }
    }

    ^readlink $registry_path | str trim
}

export def find_by_offset [bundle_id: string, offset: int] {
    let info = my_index $bundle_id
    let idx  = $info.index + $offset

    if $idx < 1 or $idx > $info.count {
        error make { msg: $"Pane offset ($offset) out of range \(have ($info.count) panes, I'm at ($info.index)\)" }
    }

    let target_raw = if not ($info.win_id | is-empty) and not ($info.tab_id | is-empty) {
        try {
            ^osascript -e $"
            tell application id \"($bundle_id)\"
                set w to first window whose id is \"($info.win_id)\"
                set tb to first tab of w whose id is \"($info.tab_id)\"
                set trm to terminal ($idx) of tb
                set trm_id to id of trm
                set pane_tty to \"\"
                try
                    set pane_tty to tty of trm
                end try
                return trm_id \u{26} \":\" \u{26} pane_tty
            end tell" | str trim
        } catch { "" }
    } else {
        try {
            ^osascript -e $"
            tell application id \"($bundle_id)\"
                set trm to terminal ($idx) of selected tab of front window
                set trm_id to id of trm
                set pane_tty to \"\"
                try
                    set pane_tty to tty of trm
                end try
                return trm_id \u{26} \":\" \u{26} pane_tty
            end tell" | str trim
        } catch { "" }
    }

    let parts = ($target_raw | split row ":")
    let target_term_id = ($parts | get 0? | default "")
    mut target_tty = ($parts | get 1? | default "")

    if ($target_tty | is-empty) {
        $target_tty = (find_tty_for_target $bundle_id $idx $info)
    }

    {
        tty: $target_tty,
        index: $idx,
        tab: $info.tab_idx,
        tab_id: $info.tab_id,
        win_id: $info.win_id,
        term_id: $target_term_id,
    }
}

# Maps printable characters to [ghostty_key_name, needs_shift]
const CHAR_TO_KEY = {
    " ":  [space,        false]
    "`":  [backquote,    false] "~":  [backquote,    true]
    "1":  [digit1,       false] "!":  [digit1,       true]
    "2":  [digit2,       false] "@":  [digit2,       true]
    "3":  [digit3,       false] "#":  [digit3,       true]
    "4":  [digit4,       false] "$":  [digit4,       true]
    "5":  [digit5,       false] "%":  [digit5,       true]
    "6":  [digit6,       false] "^":  [digit6,       true]
    "7":  [digit7,       false] "&":  [digit7,       true]
    "8":  [digit8,       false] "*":  [digit8,       true]
    "9":  [digit9,       false] "(":  [digit9,       true]
    "0":  [digit0,       false] ")":  [digit0,       true]
    "-":  [minus,        false] "_":  [minus,        true]
    "=":  [equal,        false] "+":  [equal,        true]
    "[":  [bracketLeft,  false] "{":  [bracketLeft,  true]
    "]":  [bracketRight, false] "}":  [bracketRight, true]
    "\\": [backslash,    false] "|":  [backslash,    true]
    ";":  [semicolon,    false] ":":  [semicolon,    true]
    "'":  [quote,        false] "\"": [quote,        true]
    ",":  [comma,        false] "<":  [comma,        true]
    ".":  [period,       false] ">":  [period,       true]
    "/":  [slash,        false] "?":  [slash,        true]
}

export def send_char [
    bundle_id: string,
    target: any,
    arg2: any,
    arg3?: any,
    arg4?: list<string>
] {
    let is_legacy = ($arg4 != null)
    let term_id = if ($target | describe | str starts-with "record") {
        $target.term_id? | default ""
    } else if ($target | describe | str starts-with "string") {
        $target
    } else {
        ""
    }

    let char: string = if $is_legacy { $arg3 } else { $arg2 | into string }
    let raw_modifiers: list<string> = if $is_legacy { $arg4 } else { $arg3 | default [] }

    let mapped = ($CHAR_TO_KEY | get -o $char)
    let is_ascii_letter = ($char | str lowercase) =~ '^[a-z]$'

    # Non-ASCII chars (e.g. æ, ø, å) have no Ghostty key name; send as text directly
    if $mapped == null and not $is_ascii_letter {
        try {
            if not ($term_id | is-empty) {
                ^osascript -e $"
                    tell application id \"($bundle_id)\"
                        input text \"($char)\" to \(first terminal whose id is \"($term_id)\"\)
                    end tell"
            } else {
                let idx = if ($target | describe | str starts-with "record") { $target.index } else { $target }
                let tab_idx = if $is_legacy { $arg2 | into int } else { 1 }
                ^osascript -e $"
                    tell application id \"($bundle_id)\"
                        input text \"($char)\" to terminal ($idx) of tab ($tab_idx) of front window
                    end tell"
            }
        } catch { }
        return
    }

    let key   = if $mapped != null { $mapped.0 } else { $char | str lowercase }
    let shift = if $mapped != null { $mapped.1 } else { $char != ($char | str lowercase) }

    # Strip shift from modifiers — it's handled explicitly via `extra` to avoid duplicates
    let mods_without_shift = ($raw_modifiers | where { not ($in | str contains "shift") })
    let extra = if $shift { ["shift"] } else { [] }

    let mods_str = (nu_mods_to_ghostty $mods_without_shift $extra)

    try {
        if not ($term_id | is-empty) {
            ^osascript -e $"
                tell application id \"($bundle_id)\"
                    send key \"($key)\"($mods_str) to \(first terminal whose id is \"($term_id)\"\)
                end tell"
        } else {
            let idx = if ($target | describe | str starts-with "record") { $target.index } else { $target }
            let tab_idx = if $is_legacy { $arg2 | into int } else { 1 }
            ^osascript -e $"
                tell application id \"($bundle_id)\"
                    send key \"($key)\"($mods_str) to terminal ($idx) of tab ($tab_idx) of front window
                end tell"
        }
    } catch { }
}

# Map nushell `input listen` key codes to Ghostty key names.
const NU_TO_GHOSTTY = {
    esc:       escape
    enter:     enter
    backspace: backspace
    tab:       tab
    backtab:   tab
    up:        arrowUp
    down:      arrowDown
    left:      arrowLeft
    right:     arrowRight
    home:      home
    end:       end
    pageup:    pageUp
    pagedown:  pageDown
    insert:    insert
    delete:    delete
    f1: f1  f2: f2  f3: f3  f4: f4  f5: f5  f6: f6
    f7: f7  f8: f8  f9: f9  f10: f10 f11: f11 f12: f12
}

export def send_other [
    bundle_id: string,
    target: any,
    arg2: any,
    arg3?: any,
    arg4?: list<string>
] {
    let is_legacy = ($arg4 != null)
    let term_id = if ($target | describe | str starts-with "record") {
        $target.term_id? | default ""
    } else if ($target | describe | str starts-with "string") {
        $target
    } else {
        ""
    }

    let code: string = if $is_legacy { $arg3 } else { $arg2 | into string }
    let raw_modifiers: list<string> = if $is_legacy { $arg4 } else { $arg3 | default [] }

    let ghostty_key = ($NU_TO_GHOSTTY | get -o $code)
    if $ghostty_key == null { return }

    mut extra = []
    if $code == "backtab" {
        $extra = ($extra | append "shift")
    }

    let mods_str = (nu_mods_to_ghostty $raw_modifiers $extra)
    let ghostty_key_with_mod = $"\"($ghostty_key)\" ($mods_str)"

    try {
        if not ($term_id | is-empty) {
            ^osascript -e $"
                tell application id \"($bundle_id)\"
                    send key ($ghostty_key_with_mod) to \(first terminal whose id is \"($term_id)\"\)
                end tell"
        } else {
            let idx = if ($target | describe | str starts-with "record") { $target.index } else { $target }
            let tab_idx = if $is_legacy { $arg2 | into int } else { 1 }
            ^osascript -e $"
                tell application id \"($bundle_id)\"
                    send key ($ghostty_key_with_mod) to terminal ($idx) of tab ($tab_idx) of front window
                end tell"
        }
    } catch { }
}

def nu_mods_to_ghostty [modifiers: list<string>, extra: list<string>] {
    mut mods = $extra
    if ($modifiers | any { str contains "shift" })   { $mods = ($mods | append "shift") }
    if ($modifiers | any { str contains "control" }) { $mods = ($mods | append "control") }
    if ($modifiers | any { str contains "alt" })     { $mods = ($mods | append "option") }
    if ($modifiers | any { str contains "super" })   { $mods = ($mods | append "command") }
    if ($mods | is-empty) { '' } else { $" modifiers \"($mods | uniq | str join ',')\"" }
}

export def send_input [bundle_id: string, target: any, tab_or_text: any, text?: string] {
    let term_id = if ($target | describe | str starts-with "record") {
        $target.term_id? | default ""
    } else if ($target | describe | str starts-with "string") {
        $target
    } else {
        ""
    }

    let txt = if $text != null { $text } else { $tab_or_text | into string }

    try {
        if not ($term_id | is-empty) {
            ^osascript -e $"
                tell application id \"($bundle_id)\"
                    input text \"($txt)\" to \(first terminal whose id is \"($term_id)\"\)
                end tell"
        } else {
            let idx = if ($target | describe | str starts-with "record") { $target.index } else { $target }
            let tab_idx = if $text != null { $tab_or_text | into int } else { 1 }
            ^osascript -e $"
                tell application id \"($bundle_id)\"
                    set t to terminal ($idx) of tab ($tab_idx) of front window
                    input text \"($txt)\" to t
                end tell"
        }
    } catch { }
}

export def send_enter [bundle_id: string, target: any, tab?: int] {
    let term_id = if ($target | describe | str starts-with "record") {
        $target.term_id? | default ""
    } else if ($target | describe | str starts-with "string") {
        $target
    } else {
        ""
    }

    try {
        if not ($term_id | is-empty) {
            ^osascript -e $"
                tell application id \"($bundle_id)\"
                    send key \"enter\" to \(first terminal whose id is \"($term_id)\"\)
                end tell"
        } else {
            let idx = if ($target | describe | str starts-with "record") { $target.index } else { $target }
            let tab_idx = if $tab != null { $tab } else { 1 }
            ^osascript -e $"
                tell application id \"($bundle_id)\"
                    set t to terminal ($idx) of tab ($tab_idx) of front window
                    send key \"enter\" to t
                end tell"
        }
    } catch { }
}
