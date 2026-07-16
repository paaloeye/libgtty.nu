#
#  SPDX-License-Identifier: MIT
#  Copyright (c) 2026 Paal Øye-Strømme
#
#  test_compile_layout.nu
#  libgtty.nu
#

use std/assert
use std/testing *

# Sourcing enter.nu brings compile_layout into scope
source ../enter.nu

# Use parse-time evaluation to resolve the physical directory of this test file
const test_dir = (path self | path expand | path dirname)

@test
def "test compile_layout with default config" [] {
    let kdl_path = ($test_dir | path join ".." ".workspace.default.kdl" | path expand)

    let applescript = (compile_layout
        $kdl_path
        "nvim"
        "nnn"
        "ag"
        "/tmp"
        "README.md"
        "com.mitchellh.ghostty"
    )

    assert ($applescript | str starts-with "tell application id \"com.mitchellh.ghostty\"")
    assert ($applescript | str contains "set cwd to \"/tmp\"")

    # Verify split commands are generated
    assert ($applescript | str contains "split")
    assert ($applescript | str contains "direction right")
    assert ($applescript | str contains "direction down")

    # Verify surface application commands are compiled
    assert ($applescript | str contains "nvim README.md")
    assert ($applescript | str contains "nnn")
    assert ($applescript | str contains "ag")
    assert ($applescript | str contains "gitui")

    # Verify focus and exit block
    assert ($applescript | str ends-with "focus t0_0\nend tell")
}

@test
def "test compile_layout with custom workspace config" [] {
    let kdl_path = ($test_dir | path join ".." ".workspace.kdl" | path expand)

    # If the custom .workspace.kdl exists, compile and verify it compiles without error
    if ($kdl_path | path exists) {
        let applescript = (compile_layout
            $kdl_path
            "vim"
            "nnn"
            "claude"
            "/Users/test"
            "README.md"
            "com.mitchellh.ghostty"
        )
        assert ($applescript | str starts-with "tell application id \"com.mitchellh.ghostty\"")
        assert ($applescript | str contains "focus t0_0\nend tell")
    }
}

@test
def "test compile_layout with basic fixture" [] {
    let kdl_path = ($test_dir | path join "fixtures" "workspace.basic.kdl" | path expand)

    let applescript = (compile_layout
        $kdl_path
        "nvim"
        "nnn"
        "ag"
        "/tmp"
        "README.md"
        "com.mitchellh.ghostty"
    )

    assert ($applescript | str starts-with "tell application id \"com.mitchellh.ghostty\"")
    assert ($applescript | str contains "set cwd to \"/tmp\"")
    assert ($applescript | str contains "nvim README.md")
    assert ($applescript | str ends-with "focus t0_0\nend tell")
}

@test
def "test compile_layout with horizontal break" [] {
    let kdl_path = ($test_dir | path join "fixtures" "workspace_horizontal_break.kdl" | path expand)

    let applescript = (compile_layout
        $kdl_path
        "nvim"
        "nnn"
        "ag"
        "/tmp"
        "README.md"
        "com.mitchellh.ghostty"
    )

    assert ($applescript | str contains "direction right")
    assert ($applescript | str contains "nvim README.md")
    assert ($applescript | str contains "nnn")
}

@test
def "test compile_layout with vertical break" [] {
    let kdl_path = ($test_dir | path join "fixtures" "workspace_break_v.kdl" | path expand)

    let applescript = (compile_layout
        $kdl_path
        "nvim"
        "nnn"
        "ag"
        "/tmp"
        "README.md"
        "com.mitchellh.ghostty"
    )

    assert ($applescript | str contains "direction down")
    assert ($applescript | str contains "nvim README.md")
    assert ($applescript | str contains "gitui")
}

@test
def "test compile_layout with multi pane grid" [] {
    let kdl_path = ($test_dir | path join "fixtures" "workspace_multi_pane.kdl" | path expand)

    let applescript = (compile_layout
        $kdl_path
        "nvim"
        "nnn"
        "ag"
        "/tmp"
        "README.md"
        "com.mitchellh.ghostty"
    )

    assert ($applescript | str contains "direction right")
    assert ($applescript | str contains "direction down")
    assert ($applescript | str contains "nvim README.md")
    assert ($applescript | str contains "nnn")
    assert ($applescript | str contains "ag")
    assert ($applescript | str contains "gitui")
}

@test
def "test compile_layout with suspended surface" [] {
    let kdl_path = ($test_dir | path join "fixtures" "workspace_suspended.kdl" | path expand)

    let applescript = (compile_layout
        $kdl_path
        "nvim"
        "nnn"
        "ag"
        "/tmp"
        "README.md"
        "com.mitchellh.ghostty"
    )

    # Since start_suspended is true, it should NOT send the enter key to that pane
    assert ($applescript | str contains "input text \"ag\" to t0_0")
    assert (not ($applescript | str contains "send key \"enter\" to t0_0"))
}

@test
def "test compile_layout with custom command" [] {
    let kdl_path = ($test_dir | path join "fixtures" "workspace_custom_cmd.kdl" | path expand)

    let applescript = (compile_layout
        $kdl_path
        "nvim"
        "nnn"
        "ag"
        "/tmp"
        "README.md"
        "com.mitchellh.ghostty"
    )

    assert ($applescript | str contains "input text \"htop -d 10\" to t0_0")
    assert ($applescript | str contains "send key \"enter\" to t0_0")
}

@test
def "test compile_layout with fs argv" [] {
    let kdl_path = ($test_dir | path join "fixtures" "workspace_fs_with_argv.kdl" | path expand)

    let applescript = (compile_layout
        $kdl_path
        "nvim"
        "nnn"
        "ag"
        "/tmp"
        "README.md"
        "com.mitchellh.ghostty"
    )

    assert ($applescript | str contains "input text \"nnn README.md\" to t0_0")
    assert ($applescript | str contains "send key \"enter\" to t0_0")
}
