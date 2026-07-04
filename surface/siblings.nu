#
#  SPDX-License-Identifier: MIT
#  Copyright (c) 2026 Paal Øye-Strømme
#
#  siblings.nu
#  libgtty
#

use ../completion.nu *
use lib.nu *

# Perform a one-shot or looping action on sibling Ghostty surfaces(s) by relative offset or range.
#
export def main [
    --offset: any@_panes                   # relative pane offset(s): +1, -1, -2..+1, etc.
    --action: string@_actions              # action: kill | auto-accept | focus
    --args: string@_signals = ""           # key=value pairs, comma-separated (e.g. signal=term,confirm=true)
    --max: int = 1984                      # maximum sends (auto-accept only)
    --interval: duration = 5sec            # interval between sends (auto-accept only)
    --keep-alive                           # prevent idle sleep while running (auto-accept only; display may dim)
] {
    if $offset == null {
        error make { msg: "--offset is required (e.g. +1, -1, -2..+1)" }
    }
    if ($action | is-empty) {
        error make { msg: "--action is required: kill | auto-accept | focus" }
    }

    let offsets: list<int> = match ($offset | describe) {
        "int"   => [$offset]
        "range" => ($offset | each { $in })
        _       => { error make { msg: $"--offset must be an int or range (e.g. -2..+1), got: ($offset | describe)" } }
    }

    let bundle_id = (ghostty_bundle_id)
    let targets   = $offsets | each { |o| find_by_offset $bundle_id $o }
    let opts      = (parse_args $args)

    match $action {
        "kill"        => { $targets | each { |t| do_kill $t $opts }; null }
        "auto-accept" => {
            let run = {
                if ($targets | length) == 1 {
                    do_auto_accept $bundle_id ($targets | first) $max $interval
                } else {
                    $targets | par-each { |t| do_auto_accept $bundle_id $t $max $interval }
                    null
                }
            }
            if $keep_alive {
                let caff = (job spawn { ^caffeinate -i })
                do $run
                job kill $caff
            } else {
                do $run
            }
        }
        "focus"       => { $targets | each { |t| do_focus $bundle_id $t }; null }
        _             => { error make { msg: $"Unknown action '($action)'. Valid: kill, auto-accept, focus" } }
    }
}

def parse_args [raw: string] {
    mut out = { signal: "term", confirm: true }
    if ($raw | is-empty) { return $out }
    for pair in ($raw | split row ",") {
        let kv = ($pair | split row "=" | each { str trim })
        if ($kv | length) != 2 { continue }
        $out = match ($kv | get 0) {
            "signal"  => ($out | upsert signal  ($kv | get 1))
            "confirm" => ($out | upsert confirm (($kv | get 1) == "true"))
            _         => $out
        }
    }
    $out
}

def do_kill [target: record, opts: record] {
    let tty_base = ($target.tty | path basename)
    let signame  = ($opts.signal | str upcase)

    tint $target.tty $TINT_DIM
    print $"Pane ($target.index) tinted, signal ($signame) pending"

    if $opts.confirm {
        let answer = (input $"Send ($signame) to pane ($target.index), TTY ($tty_base)? [yes/no]: " | str trim | str downcase)
        if $answer != "yes" {
            tint $target.tty ""
            print "Aborted."
            return
        }
    }

    let pids = (^ps -t $tty_base -o pid= | lines | str trim | where { not ($in | is-empty) })
    if ($pids | is-empty) {
        tint $target.tty ""
        print $"No processes found on TTY ($tty_base)"
        return
    }

    for pid in $pids {
        try { ^kill $"-($signame)" ($pid | into int) } catch { }
    }
    tint $target.tty ""
    print $"Sent ($signame) to ($pids | length) processes on TTY ($tty_base)."
}

def do_auto_accept [bundle_id: string, target: record, max: int, interval: duration] {
    let tag = $"[pane ($target.index)]"
    print $"($tag) Target: Pane=($target.index) max=($max) interval=($interval)"
    tint $target.tty $TINT_DIM
    print $"($tag) Armed \(pane tinted\). Ctrl+C to stop."

    mut count = 0
    try {
        while $count < $max {
            sleep $interval
            $count = $count + 1
            print $"($tag) [($count)/($max)] Accepting"
            tint $target.tty $TINT_FLASH
            sleep 300ms
            tint $target.tty $TINT_DIM
            send_enter $bundle_id $target.index $target.tab
        }
        tint $target.tty ""
        print $"($tag) Done. Sent ($count)/($max)."
    } catch {
        tint $target.tty ""
        print $"($tag) Disarmed."
    }
}

def do_focus [bundle_id: string, target: record] {
    ^osascript -e $"
        tell application id \"($bundle_id)\"
            focus terminal ($target.index) of selected tab of front window
        end tell"

    flash $target.tty
}
