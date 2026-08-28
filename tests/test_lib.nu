#
#  SPDX-License-Identifier: MIT
#  Copyright (c) 2026 Paal Øye-Strømme
#
#  test_lib.nu
#  libgtty.nu
#

use std/assert
use std/testing *
use ../lib.nu *

@test
def "ensure_nu_version succeeds on 0.114.0+" [] {
    # This should execute without errors on current 0.114.0+ Nushell
    ensure_nu_version
}

@test
def "ghostty_bundle_id matches env if set" [] {
    with-env { __CFBundleIdentifier: "com.test.ghostty" } {
        assert equal (ghostty_bundle_id) "com.test.ghostty"
    }
}

@test
def "ghostty_bundle_id returns safe fallback or parent identifier" [] {
    let id = (ghostty_bundle_id)
    assert (($id | str length) > 0)
    assert ($id | str starts-with "com.")
}

@test
def "current_tty returns env TTY when set" [] {
    with-env { TTY: "/dev/ttys999" } {
        assert equal (current_tty) "/dev/ttys999"
    }
}

@test
def "current_tty returns a string device or empty" [] {
    let tty_val = (current_tty)
    assert (($tty_val | describe) == "string")
}

@test
def "my_index returns expected record structure" [] {
    let id = (ghostty_bundle_id)
    let info = (my_index $id)
    assert (($info.index | describe) == "int")
    assert (($info.count | describe) == "int")
    assert (($info.tab_idx | describe) == "int")
    assert (($info.win_id | describe) == "string")
    assert (($info.tab_id | describe) == "string")
    assert (($info.term_id | describe) == "string")
}
