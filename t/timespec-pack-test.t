#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# Test the timespec packing for io_uring timeout
# struct timespec { time_t tv_sec; long tv_nsec; }

sub create_timespec {
    my ($seconds) = @_;
    my $tv_sec = int($seconds);
    my $tv_nsec = int(($seconds - $tv_sec) * 1_000_000_000);
    return pack("q q", $tv_sec, $tv_nsec);  # signed 64-bit integers
}

sub unpack_timespec {
    my ($timespec) = @_;
    my ($tv_sec, $tv_nsec) = unpack("q q", $timespec);
    return ($tv_sec, $tv_nsec);
}

# Test 1: Whole seconds
{
    my $timespec = create_timespec(5);
    my ($sec, $nsec) = unpack_timespec($timespec);
    is($sec, 5, "5 seconds -> tv_sec = 5");
    is($nsec, 0, "5 seconds -> tv_nsec = 0");
}

# Test 2: Fractional seconds
{
    my $timespec = create_timespec(2.5);
    my ($sec, $nsec) = unpack_timespec($timespec);
    is($sec, 2, "2.5 seconds -> tv_sec = 2");
    is($nsec, 500_000_000, "2.5 seconds -> tv_nsec = 500000000 (500ms)");
}

# Test 3: Small fractional value
{
    my $timespec = create_timespec(0.001);
    my ($sec, $nsec) = unpack_timespec($timespec);
    is($sec, 0, "0.001 seconds -> tv_sec = 0");
    ok($nsec >= 999_000 && $nsec <= 1_001_000, "0.001 seconds -> tv_nsec ≈ 1000000 (1ms)");
}

# Test 4: Zero timeout
{
    my $timespec = create_timespec(0);
    my ($sec, $nsec) = unpack_timespec($timespec);
    is($sec, 0, "0 seconds -> tv_sec = 0");
    is($nsec, 0, "0 seconds -> tv_nsec = 0");
}

# Test 5: Large timeout
{
    my $timespec = create_timespec(3600);
    my ($sec, $nsec) = unpack_timespec($timespec);
    is($sec, 3600, "3600 seconds -> tv_sec = 3600");
    is($nsec, 0, "3600 seconds -> tv_nsec = 0");
}

# Test 6: Complex fractional
{
    my $timespec = create_timespec(123.456789);
    my ($sec, $nsec) = unpack_timespec($timespec);
    is($sec, 123, "123.456789 seconds -> tv_sec = 123");
    ok($nsec >= 456_788_000 && $nsec <= 456_790_000, 
       "123.456789 seconds -> tv_nsec ≈ 456789000");
}

# Test 7: Very small timeout
{
    my $timespec = create_timespec(0.0000001);  # 100 nanoseconds
    my ($sec, $nsec) = unpack_timespec($timespec);
    is($sec, 0, "0.0000001 seconds -> tv_sec = 0");
    ok($nsec >= 0 && $nsec <= 200, "0.0000001 seconds -> tv_nsec ≈ 100");
}

# Test 8: Verify pack size (should be 16 bytes on 64-bit systems)
{
    my $timespec = create_timespec(1);
    my $size = length($timespec);
    is($size, 16, "timespec is 16 bytes (2 x 64-bit integers)");
}

done_testing();

__END__

=head1 NAME

timespec-pack-test.t - Verify timespec structure packing for IO::Uring

=head1 DESCRIPTION

Tests the manual timespec packing implementation used by PAL::Uring's timeout method.

The Linux struct timespec is defined as:
    struct timespec {
        time_t tv_sec;   /* seconds */
        long   tv_nsec;  /* nanoseconds */
    };

On 64-bit Linux systems, both fields are 64-bit signed integers.

=head1 WHY NOT Time::Spec?

While Time::Spec exists on CPAN, it:
- Is a very new module (released January 2026)
- Requires XS compilation
- May not be available in all CI environments
- Can fail to build on some systems

This pure-Perl pack() approach:
- Uses only core Perl functions
- Works on any Perl 5.8+
- No compilation required
- Maximum portability

=cut
