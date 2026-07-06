#
#  SPDX-License-Identifier: MIT
#  Copyright (c) 2026 Paal Øye-Strømme
#
#  test_completions.nu
#  libgtty.nu
#

use std/assert
use std/testing *
use ../completion.nu *

@test
def "test _actions returns expected completions" [] {
    let res = (_actions)
    assert (($res.completions | length) > 0)
    assert ($res.completions | any { |c| $c.value == "kill" })
    assert ($res.completions | any { |c| $c.value == "focus" })
}

@test
def "test _signals returns expected completions" [] {
    let res = (_signals)
    assert (($res.completions | length) > 0)
    assert ($res.completions | any { |c| $c.value == "signal=term" })
}

@test
def "test _ai returns expected completions" [] {
    let res = (_ai)
    assert (($res.completions | length) > 0)
    assert ($res.completions | any { |c| $c.value == "agy" })
}

@test
def "test _engines returns expected completions" [] {
    let res = (_engines)
    assert (($res.completions | length) > 0)
    assert ($res.completions | any { |c| $c.value == "nu" })
}

@test
def "test _readme returns expected completions" [] {
    let res = (_readme)
    assert ($res.options != null)
}

@test
def "test _panes cache lifecycle" [] {
    # Part 1: Seed fresh cache
    try { stor delete --table-name GTTY_SURFACES } catch {}
    stor create --table-name GTTY_SURFACES --columns { raw: str, cached_at: datetime }

    {
        raw: "ME:2\n1|/dev/ttys001|kak README.md\n3|/dev/ttys003|zzz\n4|/dev/ttys004|gitui\n",
        cached_at: (date now)
    } | stor insert --table-name GTTY_SURFACES

    let res_fresh = (_panes)
    assert (($res_fresh.completions | length) == 3)

    let comp_values = ($res_fresh.completions | get value)
    assert equal $comp_values ["-1" "+1" "+2"]

    assert ($res_fresh.completions | get 0 | get description | str contains "pane 1:")
    assert ($res_fresh.completions | get 1 | get description | str contains "pane 3:")
    assert ($res_fresh.completions | get 2 | get description | str contains "pane 4:")

    # Part 2: Seed expired cache
    try { stor delete --table-name GTTY_SURFACES } catch {}
    stor create --table-name GTTY_SURFACES --columns { raw: str, cached_at: datetime }

    {
        raw: "ME:2\n1|/dev/ttys001|kak README.md\n",
        cached_at: ((date now) - 120sec)
    } | stor insert --table-name GTTY_SURFACES

    let res_expired = (_panes)
    assert ($res_expired.completions != null)
}
