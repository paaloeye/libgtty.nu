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
