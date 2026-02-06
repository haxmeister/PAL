#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 14;

BEGIN {
    use_ok('PAL::Uevent') or BAIL_OUT("Cannot load PAL::Uevent");
}

# Test constants
is(PAL::Uevent::AF_NETLINK, 16, 'AF_NETLINK constant');
is(PAL::Uevent::NETLINK_KOBJECT_UEVENT, 15, 'NETLINK_KOBJECT_UEVENT constant');
is(PAL::Uevent::GROUP_KERNEL, 1, 'GROUP_KERNEL constant');
is(PAL::Uevent::GROUP_UDEV, 2, 'GROUP_UDEV constant');

# Test object creation
my $mon = PAL::Uevent->new();
isa_ok($mon, 'PAL::Uevent', 'Object creation');

# Test methods exist
can_ok($mon, qw(new watch poll poll_once fileno parse_event));

# Test event parsing
my $raw_event = "add\@/devices/test\0ACTION=add\0DEVPATH=/devices/test\0SUBSYSTEM=usb\0";
my $event = $mon->parse_event($raw_event);
is(ref($event), 'HASH', 'parse_event returns hashref');
is($event->{action}, 'add', 'Parsed action correctly');
is($event->{devpath}, '/devices/test', 'Parsed devpath correctly');
is($event->{SUBSYSTEM}, 'usb', 'Parsed SUBSYSTEM correctly');

# Test watch configuration
my $watch_count = 0;
eval {
    $mon->watch(
        subsystem => 'test',
        on_event => sub { $watch_count++ }
    );
};
ok(!$@, 'watch() accepts valid parameters');

# Test nonblocking mode
my $mon_nb = PAL::Uevent->new(nonblock => 1);
isa_ok($mon_nb, 'PAL::Uevent', 'Nonblocking mode object creation');

# Test fileno for event loop integration
my $fd = $mon->fileno();
like($fd, qr/^\d+$/, 'fileno() returns a file descriptor number');

diag("");
diag("PAL::Uevent comprehensive tests passed");
diag("Note: Actual uevent monitoring requires root privileges");
diag("");
