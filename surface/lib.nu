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

const TINT_TABLE = "GTTY_TINT_CACHE"
const TINT_TTL   = 300sec

def clamp_byte [val: int] {
    if $val > 255 { 255 } else if $val < 0 { 0 } else { $val }
}

def int_to_hex [val: int] {
    let clamped = (clamp_byte $val)
    let raw = ($clamped | format number | get lowerhex | str replace "0x" "")
    if ($raw | str length) == 1 { $"0($raw)" } else { $raw }
}

def hex_to_int [hex: string] {
    $"0x($hex)" | into int
}

def parse_osc11_rgb [raw: string] {
    let match = ($raw | parse -r "rgb:(?<r>[0-9a-fA-F]+)/(?<g>[0-9a-fA-F]+)/(?<b>[0-9a-fA-F]+)" | get 0?)
    if $match == null { return null }
    let r_hex = ($match.r | str substring 0..1)
    let g_hex = ($match.g | str substring 0..1)
    let b_hex = ($match.b | str substring 0..1)
    $"#($r_hex)($g_hex)($b_hex)" | str lowercase
}

def tint_cache_get [] {
    try {
        let row = (stor open | query db $"SELECT base_hex, cached_at FROM ($TINT_TABLE) LIMIT 1" | get 0?)
        if $row == null { return null }
        let age = (date now) - ($row.cached_at | into datetime)
        if $age > $TINT_TTL { return null }
        $row.base_hex
    } catch { null }
}

def tint_cache_set [base_hex: string] {
    try { stor delete --table-name $TINT_TABLE } catch { }
    try { stor create --table-name $TINT_TABLE --columns { base_hex: str, cached_at: datetime } } catch { }
    { base_hex: $base_hex, cached_at: (date now) } | stor insert --table-name $TINT_TABLE
}

# Query controlling terminal for background colour via OSC 11 with 5-minute cache
export def sample_bg_colour [] {
    let cached = (tint_cache_get)
    if $cached != null { return $cached }

    let sampled = try {
        let raw = (^bash -c "
            if [ -t 0 ] && [ -t 1 ] && [ -c /dev/tty ] && [ -r /dev/tty ] && [ -w /dev/tty ]; then
                trap '' SIGTTIN SIGTTOU
                old_stty=$(stty -g < /dev/tty 2>/dev/null) || exit 0
                stty raw -echo min 0 time 1 < /dev/tty 2>/dev/null || exit 0
                printf '\\e]11;?\\a' > /dev/tty 2>/dev/null
                resp=$(dd bs=1 count=64 < /dev/tty 2>/dev/null)
                stty \"$old_stty\" < /dev/tty 2>/dev/null
                echo \"$resp\"
            fi
        " | str trim)
        parse_osc11_rgb $raw
    } catch { null }

    let base = if $sampled != null { $sampled } else { $TINT_DIM }
    tint_cache_set $base
    $base
}

# Derive adaptive dim and flash colours from a base background colour
export def derive_tint_palette [base_hex: string] {
    let clean = ($base_hex | str trim | str replace -r "^#" "")
    if ($clean | str length) != 6 {
        return { dim: $TINT_DIM, flash: $TINT_FLASH }
    }

    let r = (hex_to_int ($clean | str substring 0..1))
    let g = (hex_to_int ($clean | str substring 2..3))
    let b = (hex_to_int ($clean | str substring 4..5))

    # Perceived luminance (ITU-R BT.709)
    let lum = ((0.2126 * $r) + (0.7152 * $g) + (0.0722 * $b))

    # Dark theme: blend with subtle dark red glow
    if $lum < 128.0 {
        let r_dim = (($r * 0.8 + 28.0) | math round | into int)
        let g_dim = (($g * 0.8) | math round | into int)
        let b_dim = (($b * 0.8 + 4.0) | math round | into int)

        let r_flash = (($r * 0.7 + 55.0) | math round | into int)
        let g_flash = (($g * 0.7) | math round | into int)
        let b_flash = (($b * 0.7 + 10.0) | math round | into int)

        return {
            dim: $"#(int_to_hex $r_dim)(int_to_hex $g_dim)(int_to_hex $b_dim)",
            flash: $"#(int_to_hex $r_flash)(int_to_hex $g_flash)(int_to_hex $b_flash)",
        }
    }

    # Light theme: shift toward soft rose/coral pastel
    let r_dim = (($r * 0.98) | math round | into int)
    let g_dim = (($g * 0.88) | math round | into int)
    let b_dim = (($b * 0.88) | math round | into int)

    let r_flash = (($r * 0.95) | math round | into int)
    let g_flash = (($g * 0.75) | math round | into int)
    let b_flash = (($b * 0.75) | math round | into int)

    {
        dim: $"#(int_to_hex $r_dim)(int_to_hex $g_dim)(int_to_hex $b_dim)",
        flash: $"#(int_to_hex $r_flash)(int_to_hex $g_flash)(int_to_hex $b_flash)",
    }
}

# Get current adaptive tint palette
export def current_tint_palette [] {
    derive_tint_palette (sample_bg_colour)
}

export def tint [tty_dev: string, colour?: string] {
    if ($tty_dev | is-empty) { return }
    let col = if $colour != null {
        $colour
    } else {
        (current_tint_palette).dim
    }
    try {
        if ($col | is-empty) or ($col == "reset") {
            ^bash -c $"printf '\\e]111\\a' > ($tty_dev)"
        } else {
            ^bash -c $"printf '\\e]11;($col)\\a' > ($tty_dev)"
        }
    } catch { }
}

export def flash [tty_dev: string, duration: duration = 300ms, colour?: string] {
    if ($tty_dev | is-empty) { return }
    let flash_col = if $colour != null {
        $colour
    } else {
        (current_tint_palette).flash
    }
    tint $tty_dev $flash_col
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
