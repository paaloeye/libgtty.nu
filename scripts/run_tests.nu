#!/usr/bin/env nu
#
#  SPDX-License-Identifier: MIT
#  Copyright (c) 2026 Paal Øye-Strømme
#
#  run_tests.nu
#  libgtty.nu
#

# Run libgtty.nu test suite using nutest
def main [
    path: string = "tests"  # Path to discover tests in (defaults to 'tests')
    --match-suites: string  # Regular expression to match against suite names
    --match-tests: string   # Regular expression to match against test names
    --fail                  # Exit with non-zero status if any tests fail
    --display: string       # Display during test run (defaults to terminal)
] {
    let root = ($env.FILE_PWD | path join ".." | path expand)
    let vendor_dir = ($root | path join "vendor" "nutest")

    if not ($vendor_dir | path exists) {
        print $"Cloning nutest into ($vendor_dir)..."
        git clone https://github.com/vyadh/nutest.git $vendor_dir # main
    }

    # Ensure tests directory exists
    if $path == "tests" and not ("tests" | path exists) {
        mkdir "tests"
    }

    mut cmd_args = ["--path" $path]

    if $match_suites != null { $cmd_args = ($cmd_args | append ["--match-suites" $match_suites]) }
    if $match_tests != null { $cmd_args = ($cmd_args | append ["--match-tests" $match_tests]) }
    if $fail { $cmd_args = ($cmd_args | append ["--fail"]) }
    if $display != null { $cmd_args = ($cmd_args | append ["--display" $display]) }

    # Run the tests from the root directory
    cd $root
    nu --no-config-file --include-path $vendor_dir -c $"use nutest; nutest run-tests ($cmd_args | str join ' ')"
}
