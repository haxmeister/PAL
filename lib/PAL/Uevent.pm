package PAL::Uevent;

use strict;
use warnings;
use Socket;
use Carp;

our $VERSION = '0.001';

=head1 NAME

PAL::Uevent - Simple interface to Linux kernel uevents (NETLINK_KOBJECT_UEVENT)

=head1 SYNOPSIS

    use PAL::Uevent;
    
    # Monitor all USB events
    my $mon = PAL::Uevent->new();
    $mon->watch(
        subsystem => 'usb',
        on_event => sub {
            my ($event) = @_;
            print "USB $event->{action}: $event->{devpath}\n";
        }
    );
    $mon->poll();  # Block and process events
    
    # Or integrate with event loop
    my $fd = $mon->fileno;
    # ... add to select/poll/epoll

=head1 DESCRIPTION

PAL::Uevent provides a simple, high-level interface to Linux kernel
uevents. These events notify userspace about hardware changes such as USB
device insertion/removal, network interface state changes, block device
hotplug, battery events, and more.

This module uses NETLINK_KOBJECT_UEVENT sockets to receive events directly
from the kernel with zero external dependencies - only core Perl modules.

=head1 FEATURES

=over 4

=item * Zero dependencies (only core Perl Socket module)

=item * Callback-based event handling

=item * Event filtering by subsystem and action

=item * Automatic uevent parsing

=item * Event loop integration via fileno()

=item * Works with all modern Linux kernels (2.6.10+)

=back

=head1 REQUIREMENTS

=over 4

=item * Linux kernel 2.6.10 or later

=item * CAP_NET_ADMIN capability or root privileges (to bind the socket)

=back

=cut

# Netlink constants
use constant {
    AF_NETLINK              => 16,
    NETLINK_KOBJECT_UEVENT  => 15,
    SOCK_DGRAM              => 2,
};

# Multicast groups
use constant {
    GROUP_KERNEL => 1,  # Raw kernel events
    GROUP_UDEV   => 2,  # Events from udevd (after processing)
};

=head1 CONSTRUCTOR

=head2 new

    my $mon = PAL::Uevent->new(%options);

Creates a new uevent monitor. Opens a netlink socket and prepares to receive
kernel events.

Options:

=over 4

=item * group => 'kernel' | 'udev' (default: 'kernel')

Which multicast group to subscribe to:
- 'kernel': Raw kernel events
- 'udev': Events from udevd (after rule processing)

=item * nonblock => 0 | 1 (default: 0)

Set socket to non-blocking mode.

=back

Throws an exception if the socket cannot be created or bound. Binding requires
CAP_NET_ADMIN capability or root privileges.

=cut

sub new {
    my ($class, %args) = @_;
    
    my $self = bless {
        group     => $args{group} || 'kernel',
        nonblock  => $args{nonblock} || 0,
        watchers  => [],
        socket    => undef,
    }, $class;
    
    # Determine multicast group
    my $group_mask = $self->{group} eq 'udev' ? GROUP_UDEV : GROUP_KERNEL;
    
    # Create netlink socket
    socket(my $sock, AF_NETLINK, SOCK_DGRAM, NETLINK_KOBJECT_UEVENT)
        or croak "Cannot create NETLINK_KOBJECT_UEVENT socket: $!";
    
    # Pack sockaddr_nl structure
    # struct sockaddr_nl {
    #     sa_family_t nl_family;  /* AF_NETLINK */
    #     unsigned short nl_pad;   /* zero */
    #     pid_t nl_pid;            /* process pid */
    #     __u32 nl_groups;         /* multicast groups mask */
    # }
    my $addr = pack("S x2 I I", AF_NETLINK, $$, $group_mask);
    
    # Bind to receive events
    bind($sock, $addr)
        or croak "Cannot bind to netlink socket: $! (requires CAP_NET_ADMIN or root)";
    
    # Set non-blocking if requested
    if ($self->{nonblock}) {
        my $flags = fcntl($sock, F_GETFL, 0)
            or croak "Cannot get socket flags: $!";
        fcntl($sock, F_SETFL, $flags | O_NONBLOCK)
            or croak "Cannot set socket non-blocking: $!";
    }
    
    $self->{socket} = $sock;
    return $self;
}

=head1 METHODS

=head2 watch

    $mon->watch(
        subsystem => 'usb',      # Optional filter
        action    => 'add',      # Optional filter
        on_event  => sub { ... } # Required callback
    );

Register a watcher callback. When events matching the filters are received,
the callback is invoked with the event as a hashref.

Filters:

=over 4

=item * subsystem => 'string' | ['str1', 'str2', ...]

Filter by subsystem (usb, block, net, power_supply, etc.)

=item * action => 'string' | ['str1', 'str2', ...]

Filter by action (add, remove, change, move, online, offline, bind, unbind)

=back

Callback receives event hashref with these standard fields:

=over 4

=item * action - Event action (add, remove, change, etc.)

=item * devpath - Device path in sysfs

=item * SUBSYSTEM - Subsystem name

=item * SEQNUM - Sequence number

=item * Plus device-specific fields (PRODUCT, DEVNAME, etc.)

=back

=cut

sub watch {
    my ($self, %args) = @_;
    
    croak "watch() requires 'on_event' callback"
        unless $args{on_event} && ref($args{on_event}) eq 'CODE';
    
    # Normalize filters to arrays
    my $subsystem_filter = $args{subsystem} 
        ? (ref($args{subsystem}) eq 'ARRAY' ? $args{subsystem} : [$args{subsystem}])
        : undef;
    
    my $action_filter = $args{action}
        ? (ref($args{action}) eq 'ARRAY' ? $args{action} : [$args{action}])
        : undef;
    
    push @{$self->{watchers}}, {
        subsystem => $subsystem_filter,
        action    => $action_filter,
        callback  => $args{on_event},
    };
}

=head2 parse_uevent

    my $event = $mon->parse_uevent($buffer);

Parse a raw uevent buffer into a hashref. This is called automatically by
read_event() but can be used standalone for testing or custom processing.

Returns undef if the buffer is empty or malformed.

=cut

sub parse_uevent {
    my ($self, $buf) = @_;
    
    return unless defined $buf && length($buf) > 0;
    
    # Split on null bytes
    my @parts = split /\0/, $buf;
    return unless @parts;
    
    # First line is action@devpath
    my $first = shift @parts;
    my ($action, $devpath) = split /@/, $first, 2;
    
    return unless defined $action && defined $devpath;
    
    # Parse KEY=VALUE pairs
    my %event = (
        action  => $action,
        devpath => $devpath,
    );
    
    for my $part (@parts) {
        next unless length($part);
        next unless $part =~ /^([A-Z_][A-Z0-9_]*)=(.*)$/;
        $event{$1} = $2;
    }
    
    return \%event;
}

=head2 read_event

    my $event = $mon->read_event();

Read and parse one event from the socket. Returns event hashref or undef
if no event is available (in non-blocking mode) or on error.

Blocks until an event arrives unless socket is in non-blocking mode.

=cut

sub read_event {
    my ($self) = @_;
    
    my $buf;
    my $result = recv($self->{socket}, $buf, 8192, 0);
    
    return unless defined $result;
    return unless length($buf) > 0;
    
    return $self->parse_uevent($buf);
}

=head2 process_event

    $mon->process_event($event);

Process an event through all registered watchers. Called automatically by
poll() and poll_once(). Can be called manually with events from other sources.

=cut

sub process_event {
    my ($self, $event) = @_;
    
    return unless $event;
    
    for my $watcher (@{$self->{watchers}}) {
        # Check subsystem filter
        if ($watcher->{subsystem}) {
            next unless $event->{SUBSYSTEM};
            my $match = 0;
            for my $sub (@{$watcher->{subsystem}}) {
                if ($event->{SUBSYSTEM} eq $sub) {
                    $match = 1;
                    last;
                }
            }
            next unless $match;
        }
        
        # Check action filter
        if ($watcher->{action}) {
            my $match = 0;
            for my $act (@{$watcher->{action}}) {
                if ($event->{action} eq $act) {
                    $match = 1;
                    last;
                }
            }
            next unless $match;
        }
        
        # Call callback
        eval {
            $watcher->{callback}->($event);
        };
        if ($@) {
            warn "Error in uevent callback: $@";
        }
    }
}

=head2 poll_once

    my $event = $mon->poll_once();

Read and process one event. Returns the event hashref or undef.

In non-blocking mode, returns immediately if no event is available.
In blocking mode, waits for an event.

=cut

sub poll_once {
    my ($self) = @_;
    
    my $event = $self->read_event();
    $self->process_event($event) if $event;
    
    return $event;
}

=head2 poll

    $mon->poll();

Enter an event loop that reads and processes events continuously.
Blocks forever (or until Ctrl-C).

For more control, use poll_once() in your own loop or integrate with
an event loop using fileno().

=cut

sub poll {
    my ($self) = @_;
    
    while (1) {
        $self->poll_once();
    }
}

=head2 fileno

    my $fd = $mon->fileno;

Returns the file descriptor of the netlink socket. Use this to integrate
with select(), poll(), epoll, or event loops like IO::Async or Mojo::IOLoop.

Example with select():

    my $rin = '';
    vec($rin, $mon->fileno, 1) = 1;
    
    while (1) {
        my $nfound = select(my $rout = $rin, undef, undef, undef);
        if ($nfound > 0) {
            $mon->poll_once();
        }
    }

=cut

sub fileno {
    my ($self) = @_;
    return fileno($self->{socket});
}

=head2 DESTROY

Cleanup method. Automatically closes the socket when the object is destroyed.

=cut

sub DESTROY {
    my ($self) = @_;
    close($self->{socket}) if $self->{socket};
}

=head1 EVENT STRUCTURE

Events are hashrefs with these common fields:

=over 4

=item * action - The event action (add, remove, change, move, online, offline, bind, unbind)

=item * devpath - Device path in sysfs (e.g., /devices/pci0000:00/0000:00:14.0/usb1/1-1)

=item * SUBSYSTEM - Kernel subsystem (usb, block, net, input, power_supply, etc.)

=item * SEQNUM - Monotonic sequence number

=back

Plus device-specific fields that vary by subsystem:

USB devices:
=over 4

=item * PRODUCT - USB vendor/product (e.g., 46d/c52b/111)

=item * TYPE - Device class

=item * BUSNUM - USB bus number

=item * DEVNUM - Device number

=back

Block devices:
=over 4

=item * DEVNAME - Device node name (e.g., sda, sda1)

=item * DEVTYPE - Device type (disk, partition)

=item * MAJOR - Major device number

=item * MINOR - Minor device number

=back

Network interfaces:
=over 4

=item * INTERFACE - Interface name (eth0, wlan0, etc.)

=item * IFINDEX - Interface index

=back

=head1 EXAMPLES

=head2 Monitor USB Devices

    my $mon = PAL::Uevent->new();
    $mon->watch(
        subsystem => 'usb',
        on_event => sub {
            my ($e) = @_;
            if ($e->{action} eq 'add') {
                print "USB device connected: $e->{PRODUCT}\n";
            } elsif ($e->{action} eq 'remove') {
                print "USB device disconnected\n";
            }
        }
    );
    $mon->poll();

=head2 Monitor Block Devices

    $mon->watch(
        subsystem => 'block',
        action => 'add',
        on_event => sub {
            my ($e) = @_;
            print "New block device: $e->{DEVNAME}\n" if $e->{DEVNAME};
        }
    );

=head2 Monitor Network Interfaces

    $mon->watch(
        subsystem => 'net',
        on_event => sub {
            my ($e) = @_;
            print "Network $e->{action}: $e->{INTERFACE}\n";
        }
    );

=head2 Multiple Subsystems

    $mon->watch(
        subsystem => ['usb', 'block', 'net'],
        on_event => sub {
            my ($e) = @_;
            print "$e->{SUBSYSTEM}: $e->{action} $e->{devpath}\n";
        }
    );

=head1 INTEGRATION WITH EVENT LOOPS

=head2 With Linux::Event

    use Linux::Event;
    use PAL::Uevent;
    
    my $loop = Linux::Event->new();
    my $mon = PAL::Uevent->new(nonblock => 1);
    
    $mon->watch(
        subsystem => 'usb',
        on_event => sub {
            my ($e) = @_;
            print "USB event: $e->{action}\n";
        }
    );
    
    $loop->io(
        fh => $mon->fileno,
        poll => 'r',
        cb => sub { $mon->poll_once() }
    );
    
    $loop->run();

=head2 With IO::Async

    use IO::Async::Loop;
    use IO::Async::Handle;
    
    my $loop = IO::Async::Loop->new;
    my $mon = PAL::Uevent->new(nonblock => 1);
    
    $loop->add(
        IO::Async::Handle->new(
            read_handle => $mon->{socket},
            on_read_ready => sub { $mon->poll_once() },
        )
    );
    
    $loop->run;

=head1 PRIVILEGES

This module requires CAP_NET_ADMIN capability or root privileges to bind
the netlink socket. This is a kernel security requirement.

Options:
=over 4

=item * Run as root

=item * Use file capabilities: setcap cap_net_admin+ep /path/to/script

=item * Use sudo

=back

=head1 KERNEL COMPATIBILITY

NETLINK_KOBJECT_UEVENT was introduced in Linux 2.6.10 (December 2004).
All modern Linux distributions support this feature.

Some advanced event types (like 'move') require newer kernels:
=over 4

=item * Basic events (add, remove, change): Linux 2.6.10+

=item * Move events: Linux 2.6.23+

=item * Bind/unbind events: Linux 3.9+

=back

=head1 SEE ALSO

=over 4

=item * L<netlink(7)> - Netlink protocol documentation

=item * L<udev(7)> - Device manager documentation

=item * Linux::Event - Event framework that can integrate with this module

=item * Linux::Inotify2 - For file change monitoring

=back

=head1 AUTHOR

Created for the Linux::Event comprehensive event framework.

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2026.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

1;
