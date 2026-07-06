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
