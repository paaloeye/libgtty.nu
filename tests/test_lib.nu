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

use ../surface/lib.nu [ derive_tint_palette current_tint_palette sample_bg_colour ]

@test
def "derive_tint_palette returns dark tint for dark background" [] {
    let palette = (derive_tint_palette "#1c1214")
    assert equal ($palette.dim | describe) "string"
    assert equal ($palette.flash | describe) "string"
    assert ($palette.dim | str starts-with "#")
    assert ($palette.flash | str starts-with "#")
}

@test
def "derive_tint_palette returns light pastel tint for light background" [] {
    let palette = (derive_tint_palette "#ffffff")
    assert equal ($palette.dim | describe) "string"
    assert equal ($palette.flash | describe) "string"
    assert ($palette.dim | str starts-with "#")
    assert ($palette.flash | str starts-with "#")
    # For white, green/blue should be lower than red (warm rose shift)
    assert equal $palette.dim "#fae0e0"
    assert equal $palette.flash "#f2bfbf"
}

@test
def "derive_tint_palette falls back on invalid hex" [] {
    let palette = (derive_tint_palette "invalid")
    assert equal $palette.dim "#1c1214"
    assert equal $palette.flash "#2a1015"
}

@test
def "current_tint_palette returns valid dim and flash hex strings" [] {
    let palette = (current_tint_palette)
    assert ($palette.dim | str starts-with "#")
    assert ($palette.flash | str starts-with "#")
}
