#
#  SPDX-License-Identifier: MIT
#  Copyright (c) 2026 Paal Øye-Strømme
#
#  lib.nu
#  libgtty.nu
#

export use ../lib.nu [ ghostty_bundle_id my_index ]

export const TINT_DIM   = "#1c1214"
export const TINT_FLASH = "#2a1015"

export def tint [tty_dev: string, colour: string = $TINT_DIM] {
    if ($colour | is-empty) {
        ^bash -c $"printf '\\e]111\\a' > ($tty_dev)"
    } else {
        ^bash -c $"printf '\\e]11;($colour)\\a' > ($tty_dev)"
    }
}

export def flash [tty_dev: string, duration: duration = 300ms] {
    tint $tty_dev $TINT_FLASH
    sleep $duration
    tint $tty_dev ""
}

export def focus [bundle_id: string, surface_index: int] {
    ^osascript -e $"
        tell application id \"($bundle_id)\"
            focus terminal ($surface_index) of selected tab of front window
        end tell"
}

export def find_tty_for_target [bundle_id: string, index: int] {
    let resolved = try {
        ^osascript -e $"tell application id \"($bundle_id)\" to get tty of terminal ($index) of selected tab of front window" e> /dev/null
            | str trim
    } catch { "" }

    if not ($resolved | is-empty) {
        return $resolved
    }

    let win_tab = (^osascript -e $"
        tell application id \"($bundle_id)\"
            return \(id of front window as text\) & \":\" & \(index of selected tab of front window as text\)
        end tell" | str trim)

    let registry_path = ([$env.XDG_RUNTIME_DIR?, $env.TMPDIR?, "/tmp"]
        | compact
        | each { |d| [$d "ghostty_panes" $"($win_tab):($index)"] | path join }
        | where { |p| $p | path exists }
        | get 0?)

    if $registry_path == null {
        let name = (^osascript -e $"tell application id \"($bundle_id)\" to get name of terminal ($index) of selected tab of front window"
            | str trim)
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

    let tab = (^osascript -e $"
        tell application id \"($bundle_id)\"
            return index of selected tab of front window as text
        end tell" | str trim | into int)

    { tty: (find_tty_for_target $bundle_id $idx), index: $idx, tab: $tab }
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

export def send_char [bundle_id: string, index: int, tab: int, char: string, modifiers: list<string>] {
    let mapped = ($CHAR_TO_KEY | get -o $char)
    let is_ascii_letter = ($char | str downcase) =~ '^[a-z]$'

    # Non-ASCII chars (e.g. æ, ø, å) have no Ghostty key name; send as text directly
    if $mapped == null and not $is_ascii_letter {
        ^osascript -e $"
            tell application id \"($bundle_id)\"
                input text \"($char)\" to terminal ($index) of tab ($tab) of front window
            end tell"
        return
    }

    let key   = if $mapped != null { $mapped.0 } else { $char | str downcase }
    let shift = if $mapped != null { $mapped.1 } else { $char != ($char | str downcase) }

    # Strip shift from modifiers — it's handled explicitly via `extra` to avoid duplicates
    let mods_without_shift = ($modifiers | where { not ($in | str contains "shift") })
    let extra = if $shift { ["shift"] } else { [] }

    let mods_str = (nu_mods_to_ghostty $mods_without_shift $extra)

    ^osascript -e $"
        tell application id \"($bundle_id)\"
            send key \"($key)\"($mods_str) to terminal ($index) of tab ($tab) of front window
        end tell"
}

# Map nushell `input listen` key codes to Ghostty key names.
const NU_TO_GHOSTTY = {
    esc:       escape
    enter:     enter
    backspace: backspace
    tab:       tab
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

export def send_other [bundle_id: string, index: int, tab: int, code: string, modifiers: list<string>] {
    let ghostty_key = ($NU_TO_GHOSTTY | get -o $code)
    if $ghostty_key == null { return }

    let mods_str = (nu_mods_to_ghostty $modifiers [])
    let ghostty_key_with_mod = $"\"($ghostty_key)\" ($mods_str)"
    # print $ghostty_key_with_mod

    ^osascript -e $"
        tell application id \"($bundle_id)\"
            send key ($ghostty_key_with_mod) to terminal ($index) of tab ($tab) of front window
        end tell"
}

def nu_mods_to_ghostty [modifiers: list<string>, extra: list<string>] {
    mut mods = $extra
    if ($modifiers | any { str contains "shift" })   { $mods = ($mods | append "shift") }
    if ($modifiers | any { str contains "control" }) { $mods = ($mods | append "control") }
    if ($modifiers | any { str contains "alt" })     { $mods = ($mods | append "option") }
    if ($modifiers | any { str contains "super" })   { $mods = ($mods | append "command") }
    if ($mods | is-empty) { '' } else { $" modifiers \"($mods | str join ',')\"" }
}

export def send_input [bundle_id: string, index: int, tab: int, text: string] {
    ^osascript -e $"
        tell application id \"($bundle_id)\"
            set t to terminal ($index) of tab ($tab) of front window
            input text \"($text)\" to t
        end tell"
}

export def send_enter [bundle_id: string, index: int, tab: int] {
    ^osascript -e $"
        tell application id \"($bundle_id)\"
            set t to terminal ($index) of tab ($tab) of front window
            send key \"enter\" to t
        end tell"
}
