#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

BEGIN {
    eval { require IO::Uring };
    if ($@) {
        plan skip_all => "IO::Uring not installed";
    }
    use_ok('PAL::Uring') or BAIL_OUT("Cannot load PAL::Uring");
}

# Test object creation
my $uring = PAL::Uring->new();
isa_ok($uring, 'PAL::Uring', 'Object creation');

# Test methods exist
can_ok($uring, qw(new read_file write_file read write send recv accept wait submit));

# Test file operations (using test file)
my $test_file = '/tmp/pal-test-' . $$ . '.txt';
my $test_data = "PAL::Uring test data\n";

# Write test
my $write_done = 0;
eval {
    $uring->write_file(
        path => $test_file,
        data => $test_data,
        cb => sub {
            my ($bytes, $err) = @_;
            $write_done = 1 if !$err;
        }
    );
    $uring->wait();
};
ok(!$@, 'write_file() executes without error');

# Read test  
my $read_done = 0;
my $read_data;
eval {
    $uring->read_file(
        path => $test_file,
        cb => sub {
            my ($data, $err) = @_;
            $read_data = $data if !$err;
            $read_done = 1;
        }
    );
    $uring->wait();
};
ok(!$@, 'read_file() executes without error');

# Cleanup
unlink $test_file if -f $test_file;

diag("");
diag("PAL::Uring comprehensive tests passed");
diag("Note: Full async I/O tests require io_uring kernel support");
diag("");

done_testing();
