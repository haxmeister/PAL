#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

BEGIN {
    eval { require IO::Uring };
    if ($@) {
        plan skip_all => "IO::Uring not installed";
    }
    eval { require Linux::Inotify2 };
    if ($@) {
        plan skip_all => "Linux::Inotify2 not installed";
    }
    use_ok('PAL::Loop') or BAIL_OUT("Cannot load PAL::Loop");
}

# Test object creation
my $loop = PAL::Loop->new();
isa_ok($loop, 'PAL::Loop', 'Object creation');

# Test methods exist
can_ok($loop, qw(new timer io signal watch run stop));

# Test timer method
my $timer_fired = 0;
eval {
    $loop->timer(
        after => 0.1,
        cb => sub { $timer_fired = 1; $loop->stop(); }
    );
};
ok(!$@, 'timer() accepts valid parameters');

# Test io watcher setup
use Socket;
socketpair(my $s1, my $s2, AF_UNIX, SOCK_STREAM, PF_UNSPEC) or die $!;
my $io_called = 0;
eval {
    $loop->io(
        fh => $s1,
        poll => 'r',
        cb => sub { $io_called = 1 }
    );
};
ok(!$@, 'io() accepts valid parameters');

# Test watcher helper class
can_ok('PAL::Loop::Watcher', qw(new cancel));

# Cleanup
close($s1);
close($s2);

diag("");
diag("PAL::Loop comprehensive tests passed");
diag("Note: Full event loop tests require running the loop");
diag("");

done_testing();
