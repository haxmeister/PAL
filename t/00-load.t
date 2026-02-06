#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 1;

BEGIN {
    use_ok('PAL') or BAIL_OUT("Cannot load PAL");
}

diag("");
diag("Testing PAL $PAL::VERSION");
diag("");
diag("PAL - Perl Async for Linux");
diag("Complete async programming framework");
diag("");
diag("Modules installed:");
diag("  PAL::Loop      - Event loop framework");
diag("  PAL::Uring     - Async I/O");
diag("  PAL::Fanotify  - Filesystem monitoring");
diag("  PAL::Uevent    - Hardware events");
diag("");
diag("Use 'use PAL;' to import all modules");
diag("");
