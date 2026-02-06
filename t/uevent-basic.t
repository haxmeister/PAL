#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

BEGIN {
    use_ok('PAL::Uevent') or BAIL_OUT("Cannot load module");
}

# Test constants
is(PAL::Uevent::AF_NETLINK, 16, 'AF_NETLINK constant');
is(PAL::Uevent::NETLINK_KOBJECT_UEVENT, 15, 'NETLINK_KOBJECT_UEVENT constant');
is(PAL::Uevent::GROUP_KERNEL, 1, 'GROUP_KERNEL constant');
is(PAL::Uevent::GROUP_UDEV, 2, 'GROUP_UDEV constant');

# Test parsing
my $mon = bless {}, 'PAL::Uevent';

# Valid uevent
my $buf = "add\@/devices/test\0ACTION=add\0DEVPATH=/devices/test\0SUBSYSTEM=test\0SEQNUM=123\0";
my $event = $mon->parse_uevent($buf);

ok($event, 'parse_uevent returns something');
is($event->{action}, 'add', 'action parsed');
is($event->{devpath}, '/devices/test', 'devpath parsed');
is($event->{ACTION}, 'add', 'ACTION field parsed');
is($event->{SUBSYSTEM}, 'test', 'SUBSYSTEM field parsed');
is($event->{SEQNUM}, '123', 'SEQNUM field parsed');

# Empty buffer
is($mon->parse_uevent(''), undef, 'empty buffer returns undef');
is($mon->parse_uevent(undef), undef, 'undef buffer returns undef');

# Malformed buffer
is($mon->parse_uevent("no-at-sign\0"), undef, 'malformed buffer returns undef');

# Test watch registration
SKIP: {
    skip "Requires root/CAP_NET_ADMIN to test socket creation", 3
        unless $< == 0 || can_bind_netlink();
    
    my $obj = eval { PAL::Uevent->new() };
    
    ok(!$@, 'constructor succeeds with privileges');
    ok($obj, 'constructor returns object');
    isa_ok($obj, 'PAL::Uevent');
}

sub can_bind_netlink {
    # Try to create and bind a netlink socket
    socket(my $sock, 16, 2, 15) or return 0;
    my $addr = pack("S x2 I I", 16, $$, 1);
    my $result = bind($sock, $addr);
    close($sock);
    return $result;
}

done_testing();
