#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# Check if we can load the module
BEGIN {
    use_ok('PAL::Uring') or BAIL_OUT("Cannot load PAL::Uring");
}

# Check if IO::Uring is available
eval { require IO::Uring; };
if ($@) {
    plan skip_all => 'IO::Uring not available (likely not on Linux with io_uring support)';
}

# Test basic constructor
{
    my $uring = PAL::Uring->new();
    isa_ok($uring, 'PAL::Uring', 'new() returns correct object');
    is($uring->pending(), 0, 'No pending operations initially');
}

# Test constructor with options
{
    my $uring = PAL::Uring->new(queue_size => 64);
    isa_ok($uring, 'PAL::Uring', 'new(queue_size) works');
    isa_ok($uring->ring(), 'IO::Uring', 'ring() returns IO::Uring object');
}

# Test read_file with a file that should exist
SKIP: {
    skip "Skipping file read test - may not work in all environments", 1 
        unless -r '/etc/hostname';
    
    my $uring = PAL::Uring->new();
    my $success = 0;
    my $data;
    
    $uring->read_file(
        path => '/etc/hostname',
        on_success => sub {
            ($data) = @_;
            $success = 1;
        },
        on_error => sub {
            fail("read_file failed: $_[0]");
        }
    );
    
    is($uring->pending(), 1, 'One pending operation after read_file');
    
    # Run the event loop
    $uring->run();
    
    ok($success, 'read_file completed successfully');
    ok(defined($data) && length($data) > 0, 'read_file returned data');
    is($uring->pending(), 0, 'No pending operations after run()');
}

# Test write_file
{
    my $uring = PAL::Uring->new();
    my $test_file = "/tmp/io_uring_easy_test_$$.txt";
    my $test_data = "Hello, PAL::Uring!\nLine 2\n";
    my $success = 0;
    
    $uring->write_file(
        path => $test_file,
        data => $test_data,
        on_success => sub {
            $success = 1;
        },
        on_error => sub {
            fail("write_file failed: $_[0]");
        }
    );
    
    $uring->run();
    
    ok($success, 'write_file completed successfully');
    ok(-f $test_file, 'File was created');
    
    # Verify contents
    if (-f $test_file) {
        open my $fh, '<', $test_file or die "Cannot read test file: $!";
        my $contents = do { local $/; <$fh> };
        close $fh;
        
        is($contents, $test_data, 'File contents match');
        
        unlink $test_file;
    }
}

# Test timeout
{
    my $uring = PAL::Uring->new();
    my $timeout_fired = 0;
    
    $uring->timeout(
        seconds => 0.1,
        on_timeout => sub {
            $timeout_fired = 1;
        }
    );
    
    $uring->run();
    
    ok($timeout_fired, 'Timeout fired');
}

# Test stop()
{
    my $uring = PAL::Uring->new();
    my $stopped_early = 0;
    
    $uring->timeout(
        seconds => 10,  # Long timeout
        on_timeout => sub {}
    );
    
    # Run with a stop condition
    $uring->run(until => sub { $stopped_early = 1; 1 });
    
    ok($stopped_early, 'run() respects until condition');
}

# Test error handling - try to read non-existent file
{
    my $uring = PAL::Uring->new();
    my $error_caught = 0;
    
    $uring->read_file(
        path => '/nonexistent/file/that/should/not/exist',
        on_success => sub {
            fail("Should not succeed reading non-existent file");
        },
        on_error => sub {
            $error_caught = 1;
        }
    );
    
    $uring->run();
    
    ok($error_caught, 'Error callback called for non-existent file');
}

done_testing();
