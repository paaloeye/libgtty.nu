#!/usr/bin/env nu
#
#  SPDX-License-Identifier: MIT
#  Copyright (c) 2026 Paal Øye-Strømme
#
#  perf_measure.nu
#  libgtty.nu
#

use ../lib.nu *
use ../enter.nu *
use ../leave.nu *

# Benchmark and profile performance of `gtty enter` and `gtty leave` workflows.
export def main [
    target: string = "all"        # target to measure: all | enter | leave | components
    --iterations (-i): int = 5    # number of iterations to average
    --json                        # output raw measurement data as JSON
] {
    ensure_nu_version

    let bundle_id = (ghostty_bundle_id)
    print $"==> libgtty.nu Performance Profiler [Target: ($target), Iterations: ($iterations)]"
    print $"==> Active Ghostty Bundle ID: ($bundle_id)"
    print ""

    match $target {
        "components" => { measure_components $bundle_id $iterations $json }
        "enter"      => { measure_enter $bundle_id $iterations $json }
        "leave"      => { measure_leave $bundle_id $iterations $json }
        "all"        => {
            print "--- Component Level Breakdown ---"
            measure_components $bundle_id $iterations $json
            print "\n--- `gtty leave` Pipeline Breakdown ---"
            measure_leave $bundle_id $iterations $json
            print "\n--- `gtty enter` Pipeline Breakdown ---"
            measure_enter $bundle_id $iterations $json
        }
        _ => {
            error make { msg: $"Unknown target: '($target)'. Choose 'all', 'enter', 'leave', or 'components'." }
        }
    }
}

# Measure core building blocks used across all commands
def measure_components [bundle_id: string, iterations: int, as_json: bool] {
    mut results = []

    for idx in 1..$iterations {
        # 1. ghostty_bundle_id
        let t0 = (date now)
        let _ = (ghostty_bundle_id)
        let d_bundle = ((date now) - $t0)

        # 2. current_tty
        let t1 = (date now)
        let _ = (current_tty)
        let d_tty = ((date now) - $t1)

        # 3. my_index query (AppleScript)
        let t2 = (date now)
        let _ = (my_index $bundle_id)
        let d_index = ((date now) - $t2)

        # 4. Raw empty osascript round-trip baseline
        let t3 = (date now)
        let _ = (try { ^osascript -e "return 1" in> /dev/null } catch { "" })
        let d_osascript_base = ((date now) - $t3)

        $results = ($results | append {
            iteration: $idx,
            ghostty_bundle_id_ms: ($d_bundle / 1ms),
            current_tty_ms: ($d_tty / 1ms),
            my_index_ms: ($d_index / 1ms),
            osascript_process_spawn_ms: ($d_osascript_base / 1ms),
        })
    }

    if $as_json {
        return ($results | to json)
    }

    let summary = [
        {
            component: "ghostty_bundle_id",
            avg_ms: (($results | get ghostty_bundle_id_ms | math avg) | math round --precision 2),
            min_ms: (($results | get ghostty_bundle_id_ms | math min) | math round --precision 2),
            max_ms: (($results | get ghostty_bundle_id_ms | math max) | math round --precision 2),
            notes: "Process tree traversal via `ps`"
        },
        {
            component: "current_tty",
            avg_ms: (($results | get current_tty_ms | math avg) | math round --precision 2),
            min_ms: (($results | get current_tty_ms | math min) | math round --precision 2),
            max_ms: (($results | get current_tty_ms | math max) | math round --precision 2),
            notes: "TTY device detection"
        },
        {
            component: "osascript process spawn",
            avg_ms: (($results | get osascript_process_spawn_ms | math avg) | math round --precision 2),
            min_ms: (($results | get osascript_process_spawn_ms | math min) | math round --precision 2),
            max_ms: (($results | get osascript_process_spawn_ms | math max) | math round --precision 2),
            notes: "Baseline CLI spawn overhead for `osascript`"
        },
        {
            component: "my_index",
            avg_ms: (($results | get my_index_ms | math avg) | math round --precision 2),
            min_ms: (($results | get my_index_ms | math min) | math round --precision 2),
            max_ms: (($results | get my_index_ms | math max) | math round --precision 2),
            notes: "Full window/tab/terminal discovery AppleScript"
        },
    ]

    print ($summary | table)
}

# Measure leave stages and compare sequential vs batched closes
def measure_leave [bundle_id: string, iterations: int, as_json: bool] {
    mut results = []

    for idx in 1..$iterations {
        let info = (my_index $bundle_id)

        # Stage 1: Terminal IDs discovery (individual call)
        let t0 = (date now)
        let terminal_ids = if not ($info.win_id | is-empty) and not ($info.tab_id | is-empty) {
            try {
                ^osascript -e $"
                tell application id \"($bundle_id)\"
                    set w to first window whose id is \"($info.win_id)\"
                    set tb to first tab of w whose id is \"($info.tab_id)\"
                    return id of every terminal of tb
                end tell" in> /dev/null | str trim | split row ", "
            } catch { [] }
        } else {
            try {
                ^osascript -e $"tell application id \"($bundle_id)\" to get id of every terminal of selected tab of front window" in> /dev/null | str trim | split row ", "
            } catch { [] }
        }
        let d_term_ids = ((date now) - $t0)

        # Stage 2: Batched query (single call to get window, tab, terminals, and focus)
        let t1 = (date now)
        let _ = try {
            ^osascript -e $"
            tell application id \"($bundle_id)\"
                set w to front window
                set tb to selected tab of w
                set all_tids to id of every terminal of tb
                set foc_tid to id of focused terminal of tb
                return \(id of w\) \u{26} \":\" \u{26} \(id of tb\) \u{26} \":\" \u{26} \(all_tids as text\) \u{26} \":\" \u{26} foc_tid
            end tell" in> /dev/null
        } catch { "" }
        let d_batched_discovery = ((date now) - $t1)

        $results = ($results | append {
            iteration: $idx,
            terminal_ids_ms: ($d_term_ids / 1ms),
            batched_discovery_ms: ($d_batched_discovery / 1ms),
            detected_terminals: ($terminal_ids | length),
        })
    }

    if $as_json {
        return ($results | to json)
    }

    let avg_term_ids = (($results | get terminal_ids_ms | math avg) | math round --precision 2)
    let avg_batched  = (($results | get batched_discovery_ms | math avg) | math round --precision 2)

    let summary = [
        {
            phase: "Current Discovery (my_index + term_ids)",
            osascript_calls: 2,
            avg_ms: $avg_term_ids,
            description: "Separate AppleScript calls to find current pane then all sibling IDs"
        },
        {
            phase: "Batched Discovery Candidate",
            osascript_calls: 1,
            avg_ms: $avg_batched,
            description: "Unified single AppleScript call returning all tab & terminal metadata"
        },
    ]

    print ($summary | table)
}

# Measure enter stages (KDL compilation vs AppleScript layout application)
def measure_enter [bundle_id: string, iterations: int, as_json: bool] {
    let module_dir = ($env.FILE_PWD | path dirname)
    let kdl_path = ($module_dir | path join ".workspace.default.kdl")

    if not ($kdl_path | path exists) {
        print $"Note: ($kdl_path) not found for enter compilation benchmark."
        return
    }

    mut results = []

    for idx in 1..$iterations {
        # 1. KDL parsing and AppleScript compilation
        let t0 = (date now)
        let script = (try {
            open --raw $kdl_path | from kdl
            "compiled"
        } catch { "" })
        let d_compile = ((date now) - $t0)

        $results = ($results | append {
            iteration: $idx,
            kdl_compile_ms: ($d_compile / 1ms),
        })
    }

    if $as_json {
        return ($results | to json)
    }

    let avg_compile = (($results | get kdl_compile_ms | math avg) | math round --precision 2)

    let summary = [
        {
            phase: "KDL Workspace Compilation",
            osascript_calls: 0,
            avg_ms: $avg_compile,
            description: "Read and parse .workspace.kdl, compute split tree and generate AppleScript"
        },
    ]

    print ($summary | table)
}
