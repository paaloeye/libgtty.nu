#
#  SPDX-License-Identifier: MIT
#  Copyright (c) 2026 Paal Øye-Strømme
#
#  completion.nu
#  libgtty
#

use lib.nu [ ghostty_bundle_id ]

const options = {
    case_sensitive: false,
    completion_algorithm: fuzzy,
    positional: false,
    sort: false,
}

# Completions for --action on `gtty siblings`
export def _actions [] {
    {
        options: $options,
        completions: [
            { value: "kill",        description: "Send a signal to processes on the target pane" }
            { value: "auto-accept", description: "Repeatedly send Enter to auto-accept agent prompts" }
            { value: "focus",       description: "Move keyboard focus to the target pane" }
        ]
    }
}

# Completions for the signal= key inside --args on `gtty siblings --action kill`
export def _signals [] {
    {
        options: $options,
        completions: [
            { value: "signal=term", description: "SIGTERM — graceful termination (default)" }
            { value: "signal=hup",  description: "SIGHUP  — hangup / reload" }
            { value: "signal=int",  description: "SIGINT  — interrupt (Ctrl+C)" }
            { value: "signal=kill", description: "SIGKILL — forceful kill, cannot be caught" }
            { value: "signal=quit", description: "SIGQUIT — quit with core dump" }
        ]
    }
}

const SURFACES_TABLE = "GTTY_SURFACES"
const SURFACES_TTL   = 60sec

def panes_cache_get [] {
    try {
        let row = (stor open | query db $"SELECT raw, cached_at FROM ($SURFACES_TABLE) LIMIT 1" | get 0?)
        if $row == null { return null }
        let age = (date now) - $row.cached_at
        if $age > $SURFACES_TTL { return null }
        $row.raw
    } catch { null }
}

def panes_cache_set [raw: string] {
    try { stor delete --table-name $SURFACES_TABLE } catch { }
    try { stor create --table-name $SURFACES_TABLE --columns { raw: str, cached_at: datetime } } catch { }
    { raw: $raw, cached_at: (date now) } | stor insert --table-name $SURFACES_TABLE
}

# Completions for --pane on `gtty siblings` — live offsets relative to the focused pane
export def _panes [] {
    let raw = panes_cache_get

    let raw = if $raw != null { $raw } else {
        let bundle_id = (ghostty_bundle_id)
        let fetched = try {
            ^osascript -e ($"tell application id \"($bundle_id)\"" + '
                    set n   to count terminals of selected tab of front window
                    set fid to id of focused terminal of selected tab of front window
                    set out to ""
                    repeat with i from 1 to n
                        set t to terminal i of selected tab of front window
                        if id of t is fid then
                            set out to out & "ME:" & (i as text) & "\n"
                        else
                            set pane_tty to ""
                            try
                                set pane_tty to tty of t
                            end try
                            set out to out & (i as text) & "|" & pane_tty & "|" & (name of t) & "\n"
                        end if
                    end repeat
                    return out
                end tell') | str trim
        } catch { "" }
        if not ($fetched | is-empty) { panes_cache_set $fetched }
        $fetched
    }

    if ($raw | is-empty) { return { options: $options, completions: [] } }

    let lines   = ($raw | lines | where { not ($in | is-empty) })
    let me_line = ($lines | where { $in | str starts-with "ME:" } | get 0?)
    if $me_line == null { return { options: $options, completions: [] } }

    let me = ($me_line | str replace "ME:" "" | into int)

    let completions = ($lines
        | where { not ($in | str starts-with "ME:") }
        | each { |line|
            let parts   = ($line | split row "|")
            let idx     = ($parts | get 0 | str trim | into int)
            let tty     = ($parts | get -o 1 | default "" | str trim)
            let name    = ($parts | skip 2 | str join "|" | str trim)
            let offset  = $idx - $me
            let tty_base = ($tty | path basename)
            let fg_cmd  = if not ($tty_base | is-empty) {
                try {
                    ^ps -t $tty_base -o stat=,comm=
                        | lines
                        | where { $in | str contains "+" }
                        | get 0?
                        | default ""
                        | str replace -r '^[^\s]+\s+' ""
                        | path basename
                } catch { "" }
            } else { "" }
            let cmd_col = if ($fg_cmd | is-empty) {
                " " | fill -w 15
            } else {
                let t = if ($fg_cmd | str length) > 13 { ($fg_cmd | str substring 0..9) + "..." } else { $fg_cmd }
                $"▶ ($t)" | fill -w 15
            }
            let desc = $"($cmd_col)  ($tty_base)  pane ($idx): ($name)"
            {
                value:       (if $offset > 0 { $"+($offset)" } else { $offset | into string }),
                description: $desc
            }
        })

    { options: $options, completions: $completions }
}

# Completions for --ai on `gtty enter`
export def _ai [] {
    {
        options: $options,
        completions: [
            { value: "agy",    description: "Antigravity CLI (Google)" }
            { value: "claude", description: "Claude Code (Anthropic)" }
            { value: "gemini", description: "Gemini CLI (Google)" }
            { value: "pi",     description: "Pi (pi.dev)" }
        ]
    }
}

export def _engines [] {
    {
        options: $options,
        completions: [
            { value: "swift", description: "Swift" }
            { value: "nu", description: "Nushell" }
        ]
    }
}

# Completions for --file on `gtty enter`
export def _readme [] {
    let candidates = ["README.md" "README.adoc" "README.asciidoc"]
    let found = ($candidates | where { ($env.PWD | path join $in) | path exists })

    {
        options: ($options | upsert sort false),
        completions: ($found | each { { value: $in } })
    }
}
