#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# Check if we can load the module
BEGIN {
    use_ok('PAL::Fanotify') or BAIL_OUT("Cannot load PAL::Fanotify");
}

# Check if Linux::Fanotify is available
eval { require Linux::Fanotify; };
if ($@) {
    plan skip_all => 'Linux::Fanotify not available';
}

# Check if running as root
unless ($> == 0) {
    plan skip_all => 'Tests require root privileges (fanotify needs CAP_SYS_ADMIN)';
}

# Test basic constructor
{
    my $fan = eval { PAL::Fanotify->new() };
    
    if ($@) {
        # If fanotify isn't available on this system, skip remaining tests
        if ($@ =~ /permission/i) {
            plan skip_all => 'Fanotify requires root privileges';
        } elsif ($@ =~ /not available/i) {
            plan skip_all => 'Fanotify not available on this system';
        } else {
            fail("Constructor failed: $@");
        }
    }
    
    isa_ok($fan, 'PAL::Fanotify', 'new() returns correct object');
}

# Test constructor with options
{
    my $fan = PAL::Fanotify->new(
        flags => ['nonblock'],
        class => 'notif',
    );
    
    isa_ok($fan, 'PAL::Fanotify', 'new(options) works');
    ok(defined($fan->fd), 'fd() returns a file descriptor');
    ok($fan->fd >= 0, 'fd() returns valid number');
}

# Test watch creation
{
    my $fan = PAL::Fanotify->new(flags => ['nonblock']);
    
    my $watch = $fan->watch(
        path => '/tmp',
        events => ['open'],
        on_event => sub { }
    );
    
    isa_ok($watch, 'PAL::Fanotify::Watch', 'watch() returns watch object');
    ok($watch->is_active(), 'Watch is active initially');
}

# Test event detection
SKIP: {
    skip "File operation tests", 3 unless -w '/tmp';
    
    my $fan = PAL::Fanotify->new(flags => ['nonblock']);
    my $event_fired = 0;
    my $test_file = "/tmp/fanotify_easy_test_$$.txt";
    
    $fan->watch(
        path => '/tmp',
        events => ['open', 'close_write'],
        on_event => sub {
            my ($event) = @_;
            $event_fired++ if $event->{path} eq $test_file;
        }
    );
    
    # Create and write to file
    open my $fh, '>', $test_file or die "Cannot create test file: $!";
    print $fh "test data\n";
    close $fh;
    
    # Poll for events
    for (1..10) {
        $fan->poll();
        last if $event_fired;
        select(undef, undef, undef, 0.1);
    }
    
    ok($event_fired > 0, 'Events detected');
    
    # Cleanup
    unlink $test_file if -e $test_file;
}

# Test watch stop
{
    my $fan = PAL::Fanotify->new(flags => ['nonblock']);
    
    my $watch = $fan->watch(
        path => '/tmp',
        events => ['open'],
        on_event => sub { }
    );
    
    ok($watch->is_active(), 'Watch active before stop');
    $watch->stop();
    ok(!$watch->is_active(), 'Watch inactive after stop');
}

# Test error callback
{
    my $error_message;
    
    my $fan = PAL::Fanotify->new(
        flags => ['nonblock'],
        on_error => sub {
            $error_message = shift;
        }
    );
    
    isa_ok($fan, 'PAL::Fanotify', 'Constructor with error callback works');
}

# Test invalid arguments
{
    my $fan = PAL::Fanotify->new();
    
    eval {
        $fan->watch(
            # Missing required parameters
            path => '/tmp'
        );
    };
    ok($@, 'Dies when required parameters missing');
    like($@, qr/required/, 'Error message mentions required parameters');
}

done_testing();
