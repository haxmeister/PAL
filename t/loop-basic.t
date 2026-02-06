#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# Check if we can load the module
BEGIN {
    use_ok('PAL::Loop') or BAIL_OUT("Cannot load PAL::Loop");
}

# Check if IO::Uring is available
eval { require IO::Uring; };
if ($@) {
    plan skip_all => 'IO::Uring not available (likely not on Linux with io_uring support)';
}

# Test basic constructor
{
    my $loop = PAL::Loop->new();
    isa_ok($loop, 'PAL::Loop', 'new() returns correct object');
    ok(!$loop->is_running(), 'Loop not running initially');
}

# Test constructor with options
{
    my $loop = PAL::Loop->new(
        queue_size => 128,
        max_events => 16
    );
    isa_ok($loop, 'PAL::Loop', 'new(options) works');
}

# Test timer
{
    my $loop = PAL::Loop->new();
    my $fired = 0;
    
    my $timer = $loop->timer(
        after => 0.1,
        cb => sub {
            $fired = 1;
            $loop->stop();
        }
    );
    
    isa_ok($timer, 'PAL::Loop::Watcher', 'timer returns watcher');
    ok($timer->is_active(), 'Timer is active');
    
    $loop->run();
    
    ok($fired, 'Timer callback fired');
    ok(!$timer->is_active(), 'Timer deactivated after firing');
}

# Test periodic timer
{
    my $loop = PAL::Loop->new();
    my $count = 0;
    
    my $periodic = $loop->periodic(
        interval => 0.1,
        cb => sub {
            $count++;
        }
    );
    
    $loop->timer(
        after => 0.35,
        cb => sub {
            $periodic->stop();
            $loop->stop();
        }
    );
    
    $loop->run();
    
    ok($count >= 2 && $count <= 4, "Periodic fired ~3 times (got $count)");
}

# Test defer
{
    my $loop = PAL::Loop->new();
    my @order;
    
    push @order, 1;
    
    $loop->defer(sub {
        push @order, 3;
        $loop->stop();
    });
    
    push @order, 2;
    
    $loop->run();
    
    is_deeply(\@order, [1, 2, 3], 'Deferred callback ran after current code');
}

# Test watcher control
{
    my $loop = PAL::Loop->new();
    my $count = 0;
    
    my $periodic = $loop->periodic(
        interval => 0.05,
        cb => sub { $count++ }
    );
    
    # Stop immediately
    $periodic->stop();
    
    # Let some time pass
    $loop->timer(
        after => 0.2,
        cb => sub { $loop->stop() }
    );
    
    $loop->run();
    
    is($count, 0, 'Stopped watcher did not fire');
    
    # Now start it
    $count = 0;
    $periodic->start();
    
    $loop->timer(
        after => 0.15,
        cb => sub {
            $periodic->stop();
            $loop->stop();
        }
    );
    
    $loop->run();
    
    ok($count >= 1, 'Restarted watcher fired');
}

# Test watcher data
{
    my $loop = PAL::Loop->new();
    
    my $timer = $loop->timer(
        after => 0.1,
        data => { foo => 'bar', baz => 42 },
        cb => sub {
            my ($watcher) = @_;
            my $data = $watcher->data();
            is($data->{foo}, 'bar', 'Watcher data preserved (string)');
            is($data->{baz}, 42, 'Watcher data preserved (number)');
            $loop->stop();
        }
    );
    
    $loop->run();
}

# Test priority (basic)
{
    my $loop = PAL::Loop->new();
    
    my $timer = $loop->timer(after => 0.1, cb => sub {});
    
    is($timer->priority(), 0, 'Default priority is 0');
    
    $timer->priority(10);
    is($timer->priority(), 10, 'Priority can be set');
}

# Test now()
{
    my $loop = PAL::Loop->new();
    my $now = $loop->now();
    
    ok($now > 0, 'now() returns a timestamp');
    ok(abs($now - time()) < 1, 'now() is close to time()');
}

done_testing();
