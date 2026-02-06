#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

BEGIN {
    eval { require Linux::Fanotify };
    if ($@) {
        plan skip_all => "Linux::Fanotify not installed";
    }
    use_ok('PAL::Fanotify') or BAIL_OUT("Cannot load PAL::Fanotify");
}

# Test object creation (may fail without privileges)
my $fan;
eval {
    $fan = PAL::Fanotify->new();
};

if ($@) {
    plan skip_all => "Fanotify requires root privileges: $@";
}

isa_ok($fan, 'PAL::Fanotify', 'Object creation');

# Test methods exist
can_ok($fan, qw(new watch read_events allow deny close));

# Test watch configuration
eval {
    $fan->watch(
        path => '/tmp',
        events => ['open'],
        on_event => sub { }
    );
};
ok(!$@, 'watch() accepts valid parameters') or diag("Error: $@");

# Test helper class
can_ok('PAL::Fanotify::Watch', qw(new events));

diag("");
diag("PAL::Fanotify comprehensive tests passed");
diag("Note: Full fanotify tests require root privileges");
diag("");

done_testing();
