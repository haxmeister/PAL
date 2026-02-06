#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 8;

# Test that all modules can be loaded together
use_ok('PAL');
use_ok('PAL::Loop');
use_ok('PAL::Uring');
use_ok('PAL::Fanotify');
use_ok('PAL::Uevent');

# Test PAL meta-module import
{
    package TestPackage;
    eval { PAL->import() };
}
ok(!$@, 'PAL->import() works without errors');

# Test version consistency
ok(defined $PAL::VERSION, 'PAL has a version');
is($PAL::VERSION, '0.001', 'PAL version is 0.001');

diag("");
diag("PAL Integration Tests");
diag("All modules loaded successfully together");
diag("Framework version: $PAL::VERSION");
diag("");
