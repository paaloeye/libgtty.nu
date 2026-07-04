#
#  SPDX-License-Identifier: MIT
#  Copyright (c) 2026 Paal Øye-Strømme
#
#  broadcast.nu
#  libgtty
#

use ../completion.nu *
use lib.nu *

# Broadcast typed input in a loop to one or more sibling Ghostty surfaces.
#
# Loops until Ctrl+C or Ctrl+D.
#
export def main [
    --offset: any@_panes                # Relative surface offset(s): +1, -1, -2..+1, etc.
    --engine: string@_engines = "swift" # Engine. (default "swift")
] {
    if $offset == null {
        error make { msg: "--offset is required (e.g. +1, -1, -2..+1)" }
    }

    if $engine == "swift" {
        const bin = (path self
            | path expand
            | path dirname
            | path join "broadcast" ".build" "release" "gtty-surface-broadcast")
        exec $bin $"($offset)"
    }

    let offsets: list<int> = match ($offset | describe) {
        "int"   => [$offset]
        "range" => ($offset | each { $in })
        _       => { error make { msg: $"--offset must be an int or range, got: ($offset | describe)" } }
    }

    let bundle_id = (ghostty_bundle_id)
    let targets = $offsets | each { |o| find_by_offset $bundle_id $o }
    let source = (my_index $bundle_id)

    print $"Broadcasting to ($targets | length) pane\(s\). Ctrl+C / Ctrl+D to stop."
    print --no-newline "> "

    try {
        loop {
            let key = (input listen --types [key])
            # print ($key | to nuon)

            # match flags
            let ctrl = ($key.modifiers | any { str contains "control" })
            let ascii = ($key.code | encode utf8 | first) <= 127

            match [$key.key_type $key.code $ctrl $ascii] {
                # exit
                ["char" "c" true _] | ["char" "d" true] => { break }

                # non-ASCII chars (e.g. æ, ø, å) have no Ghostty key name; send as text directly
                ["char" _ _ false]  => {
                    for t in $targets { send_input $bundle_id $t.index $t.tab $key.code }
                }

                # send via `send_char`
                ["char" _ _ _]  => {
                    for t in $targets { send_char $bundle_id $t.index $t.tab $key.code $key.modifiers }
                }

                # Workaround: escape steals focus via AppKit cancelOperation: responder chain.
                ["other" "esc" _ _] => {
                    for t in $targets { send_other $bundle_id $t.index $t.tab $key.code $key.modifiers }

                    # Restore focus
                    focus $bundle_id $source.index
                }

                # send via `send_other`
                ["other" _ _ _] => {
                    for t in $targets { send_other $bundle_id $t.index $t.tab $key.code $key.modifiers }
                }
                _ => {}
            }
        }
    } catch { |e| print $"\nError: ($e.msg)" }

    print "Broadcast ended."
}
