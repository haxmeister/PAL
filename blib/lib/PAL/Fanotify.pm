package PAL::Fanotify;

use strict;
use warnings;
use Linux::Fanotify;
use Carp qw(croak carp);
use Scalar::Util qw(weaken);

our $VERSION = '0.001';

=head1 NAME

PAL::Fanotify - Simplified interface to Linux::Fanotify

=head1 SYNOPSIS

    use PAL::Fanotify;
    
    # Create a new fanotify instance
    my $fan = PAL::Fanotify->new(
        flags => ['nonblock'],
        on_error => sub {
            my ($error) = @_;
            warn "Error: $error\n";
        }
    );
    
    # Watch a mount point
    $fan->watch(
        path => '/home',
        events => ['open', 'close_write', 'create'],
        on_event => sub {
            my ($event) = @_;
            printf "PID %d: %s on %s\n", 
                $event->{pid}, $event->{event}, $event->{path};
        }
    );
    
    # Process events
    while (1) {
        $fan->poll();
    }

=head1 DESCRIPTION

PAL::Fanotify provides a simplified, user-friendly interface to 
Linux::Fanotify. Instead of dealing with low-level file descriptors, bitmasks,
and manual path resolution, this module provides:

=over 4

=item * Named parameters instead of bitwise flags

=item * Automatic path resolution from file descriptors

=item * Callback-based event handling

=item * Event names as strings (not bitmasks)

=item * Automatic permission response handling

=item * Better error messages

=item * Event loop friendly design

=back

=head1 METHODS

=head2 new(%options)

Create a new fanotify instance.

Options:

=over 4

=item * flags - Array of flag names: 'nonblock', 'cloexec', 'unlimited_queue', 'unlimited_marks' (optional)

=item * class - Notification class: 'notif', 'content', 'pre_content' (default: 'notif')

=item * on_error - Error callback (optional)

=back

    my $fan = PAL::Fanotify->new(
        flags => ['nonblock'],
        class => 'notif',
    );

Requires: Root privileges (CAP_SYS_ADMIN), Linux 2.6.37+

=cut

sub new {
    my ($class, %opts) = @_;
    
    my $flags_array = delete $opts{flags} || [];
    my $class_name = delete $opts{class} || 'notif';
    my $on_error = delete $opts{on_error};
    
    # Convert flag names to constants
    my $init_flags = 0;
    my %flag_map = (
        'nonblock'        => Linux::Fanotify::FAN_NONBLOCK(),
        'cloexec'         => Linux::Fanotify::FAN_CLOEXEC(),
        'unlimited_queue' => Linux::Fanotify::FAN_UNLIMITED_QUEUE(),
        'unlimited_marks' => Linux::Fanotify::FAN_UNLIMITED_MARKS(),
    );
    
    for my $flag (@$flags_array) {
        my $flag_lc = lc($flag);
        croak "Unknown flag: $flag" unless exists $flag_map{$flag_lc};
        $init_flags |= $flag_map{$flag_lc};
    }
    
    # Convert class name to constant
    my %class_map = (
        'notif'       => Linux::Fanotify::FAN_CLASS_NOTIF(),
        'content'     => Linux::Fanotify::FAN_CLASS_CONTENT(),
        'pre_content' => Linux::Fanotify::FAN_CLASS_PRE_CONTENT(),
    );
    
    my $class_lc = lc($class_name);
    croak "Unknown class: $class_name" unless exists $class_map{$class_lc};
    $init_flags |= $class_map{$class_lc};
    
    # Create fanotify group
    my $group = Linux::Fanotify::FanotifyGroup->new(
        $init_flags,
        Linux::Fanotify::O_RDONLY() | Linux::Fanotify::O_LARGEFILE()
    );
    
    unless ($group) {
        my $error = $!;
        if ($error =~ /permission/i) {
            croak "Failed to create fanotify instance: Permission denied (are you root?)";
        } else {
            croak "Failed to create fanotify instance: $error";
        }
    }
    
    my $self = bless {
        group => $group,
        on_error => $on_error,
        watches => [],
        event_callbacks => {},  # event_id => callback
    }, $class;
    
    return $self;
}

=head2 watch(%options)

Add a watch to the fanotify instance.

Options:

=over 4

=item * path - Path to watch (file, directory, or mount point) (required)

=item * events - Array of event names to watch (required)

=item * mark_type - Type of mark: 'mount', 'filesystem', 'inode' (default: 'mount')

=item * on_event - Event callback (required)

=back

Event names: 'access', 'modify', 'close_write', 'close_nowrite', 'open',
'open_exec', 'attrib', 'create', 'delete', 'delete_self', 'moved_from',
'moved_to', 'move_self', 'open_perm', 'access_perm'.

Note: create/delete/move events require Linux 5.1+

The callback receives a hashref with: path, event, mask, pid, fd

    my $watch = $fan->watch(
        path => '/home',
        events => ['open', 'close_write'],
        on_event => sub {
            my ($event) = @_;
            print "$event->{event} on $event->{path} by PID $event->{pid}\n";
        }
    );

Returns a watch object that can be stopped with $watch->stop().

=cut

sub watch {
    my ($self, %opts) = @_;
    
    my $path = delete $opts{path} or croak "path is required";
    my $events = delete $opts{events} or croak "events is required";
    my $mark_type = delete $opts{mark_type} || 'mount';
    my $on_event = delete $opts{on_event} or croak "on_event callback is required";
    
    croak "events must be an array reference" unless ref($events) eq 'ARRAY';
    croak "Invalid mark_type: $mark_type" unless $mark_type =~ /^(mount|filesystem|inode)$/;
    
    # Convert event names to mask
    my $mask = 0;
    my %event_map = (
        'access'        => Linux::Fanotify::FAN_ACCESS(),
        'modify'        => Linux::Fanotify::FAN_MODIFY(),
        'close_write'   => Linux::Fanotify::FAN_CLOSE_WRITE(),
        'close_nowrite' => Linux::Fanotify::FAN_CLOSE_NOWRITE(),
        'open'          => Linux::Fanotify::FAN_OPEN(),
        'open_exec'     => Linux::Fanotify::FAN_OPEN_EXEC(),
    );
    
    # Linux 5.1+ events (if available)
    if (Linux::Fanotify->can('FAN_CREATE')) {
        $event_map{attrib}      = Linux::Fanotify::FAN_ATTRIB();
        $event_map{create}      = Linux::Fanotify::FAN_CREATE();
        $event_map{delete}      = Linux::Fanotify::FAN_DELETE();
        $event_map{delete_self} = Linux::Fanotify::FAN_DELETE_SELF();
        $event_map{moved_from}  = Linux::Fanotify::FAN_MOVED_FROM();
        $event_map{moved_to}    = Linux::Fanotify::FAN_MOVED_TO();
        $event_map{move_self}   = Linux::Fanotify::FAN_MOVE_SELF();
    }
    
    # Permission events
    $event_map{open_perm}   = Linux::Fanotify::FAN_OPEN_PERM();
    $event_map{access_perm} = Linux::Fanotify::FAN_ACCESS_PERM();
    
    for my $event (@$events) {
        my $event_lc = lc($event);
        if (exists $event_map{$event_lc}) {
            $mask |= $event_map{$event_lc};
        } else {
            carp "Unknown or unsupported event: $event (may require Linux 5.1+)";
        }
    }
    
    # Determine mark flags
    my $mark_flags = Linux::Fanotify::FAN_MARK_ADD();
    if ($mark_type eq 'mount') {
        $mark_flags |= Linux::Fanotify::FAN_MARK_MOUNT();
    } elsif ($mark_type eq 'filesystem') {
        $mark_flags |= Linux::Fanotify::FAN_MARK_FILESYSTEM();
    }
    # 'inode' uses no additional flags
    
    # Add the mark
    my $dirfd = -1;  # AT_FDCWD
    my $result = $self->{group}->mark($mark_flags, $mask, $dirfd, $path);
    
    unless ($result) {
        my $error = $!;
        if ($error =~ /permission/i) {
            croak "Failed to mark $path: Permission denied (are you root?)";
        } elsif ($error =~ /invalid/i) {
            croak "Failed to mark $path: Invalid argument (check event support for your kernel)";
        } else {
            croak "Failed to mark $path: $error";
        }
    }
    
    my $watch = bless {
        fanotify => $self,
        path => $path,
        events => $events,
        mark_type => $mark_type,
        mask => $mask,
        mark_flags => $mark_flags,
        callback => $on_event,
        active => 1,
    }, 'PAL::Fanotify::Watch';
    
    push @{$self->{watches}}, $watch;
    
    return $watch;
}

=head2 poll($count)

Poll for events and invoke callbacks.

    # Process one event
    my $processed = $fan->poll(1);
    
    # Process up to 10 events
    my $processed = $fan->poll(10);
    
    # Process all available events
    my $processed = $fan->poll();

Returns the number of events processed.

This method reads events from the fanotify file descriptor and invokes
the appropriate callbacks. For non-blocking instances, returns immediately
if no events are available.

=cut

sub poll {
    my ($self, $count) = @_;
    
    $count ||= 100;  # Default to processing up to 100 events
    
    my @events = eval { $self->{group}->read($count) };
    if ($@) {
        if ($self->{on_error}) {
            $self->{on_error}->("Failed to read events: $@");
        }
        return 0;
    }
    
    my $processed = 0;
    
    for my $event (@events) {
        $processed++;
        
        # Convert event to friendly format
        my $event_data = $self->_process_event($event);
        
        # Invoke callbacks for matching watches
        for my $watch (@{$self->{watches}}) {
            next unless $watch->{active};
            
            # Check if this event matches the watch's mask
            if ($event->mask & $watch->{mask}) {
                eval {
                    $watch->{callback}->($event_data);
                };
                if ($@) {
                    if ($self->{on_error}) {
                        $self->{on_error}->("Callback died: $@");
                    } else {
                        carp "Watch callback died: $@";
                    }
                }
            }
        }
    }
    
    return $processed;
}

sub _process_event {
    my ($self, $event) = @_;
    
    my $mask = $event->mask;
    my $pid = $event->pid;
    my $fd = $event->fd;
    
    # Resolve path from file descriptor
    my $path = $self->_get_path_from_fd($fd);
    
    # Convert mask to event name(s)
    my @event_names;
    
    push @event_names, 'access' if $mask & Linux::Fanotify::FAN_ACCESS();
    push @event_names, 'modify' if $mask & Linux::Fanotify::FAN_MODIFY();
    push @event_names, 'close_write' if $mask & Linux::Fanotify::FAN_CLOSE_WRITE();
    push @event_names, 'close_nowrite' if $mask & Linux::Fanotify::FAN_CLOSE_NOWRITE();
    push @event_names, 'open' if $mask & Linux::Fanotify::FAN_OPEN();
    push @event_names, 'open_exec' if $mask & Linux::Fanotify::FAN_OPEN_EXEC();
    
    if (Linux::Fanotify->can('FAN_CREATE')) {
        push @event_names, 'attrib' if $mask & Linux::Fanotify::FAN_ATTRIB();
        push @event_names, 'create' if $mask & Linux::Fanotify::FAN_CREATE();
        push @event_names, 'delete' if $mask & Linux::Fanotify::FAN_DELETE();
        push @event_names, 'delete_self' if $mask & Linux::Fanotify::FAN_DELETE_SELF();
        push @event_names, 'moved_from' if $mask & Linux::Fanotify::FAN_MOVED_FROM();
        push @event_names, 'moved_to' if $mask & Linux::Fanotify::FAN_MOVED_TO();
        push @event_names, 'move_self' if $mask & Linux::Fanotify::FAN_MOVE_SELF();
    }
    
    push @event_names, 'open_perm' if $mask & Linux::Fanotify::FAN_OPEN_PERM();
    push @event_names, 'access_perm' if $mask & Linux::Fanotify::FAN_ACCESS_PERM();
    
    my $event_str = join(',', @event_names) || 'unknown';
    
    # Check if this is a permission event
    my $is_perm = ($mask & Linux::Fanotify::FAN_OPEN_PERM()) || 
                  ($mask & Linux::Fanotify::FAN_ACCESS_PERM());
    
    return {
        path => $path,
        event => $event_str,
        mask => $mask,
        pid => $pid,
        fd => $fd,
        is_permission => $is_perm,
        _raw_event => $event,
    };
}

sub _get_path_from_fd {
    my ($self, $fd) = @_;
    
    return 'unknown' unless defined $fd && $fd >= 0;
    
    my $proc_path = "/proc/self/fd/$fd";
    my $path = readlink($proc_path);
    
    return $path || 'unknown';
}

=head2 fd()

Get the file descriptor for the fanotify instance.

    my $fd = $fan->fd();

This is useful for integrating with event loops like select(), poll(),
or epoll().

=cut

sub fd {
    my ($self) = @_;
    return $self->{group}->fd();
}

=head2 allow($event)

Allow a permission event.

    $fan->watch(
        path => '/secure',
        events => ['open_perm'],
        on_event => sub {
            my ($event) = @_;
            
            if ($event->{path} =~ /\.txt$/) {
                $fan->allow($event);
            } else {
                $fan->deny($event);
            }
        }
    );

=cut

sub allow {
    my ($self, $event_data) = @_;
    
    return unless $event_data->{is_permission};
    
    my $event = $event_data->{_raw_event};
    $event->allow();
}

=head2 deny($event, $error)

Deny a permission event.

    $fan->deny($event);           # Returns EPERM
    $fan->deny($event, 'EACCES'); # Returns EACCES

=cut

sub deny {
    my ($self, $event_data, $error) = @_;
    
    return unless $event_data->{is_permission};
    
    my $event = $event_data->{_raw_event};
    $event->deny();
}

=head1 WATCH METHODS

Watch objects returned by watch() support:

=head2 $watch->stop()

Stop receiving events for this watch.

    my $watch = $fan->watch(...);
    $watch->stop();

=head2 $watch->is_active()

Check if watch is active.

    if ($watch->is_active()) {
        print "Watch is active\n";
    }

=cut

package PAL::Fanotify::Watch;

sub stop {
    my ($self) = @_;
    
    return unless $self->{active};
    
    # Remove the mark
    my $mark_flags = Linux::Fanotify::FAN_MARK_REMOVE();
    if ($self->{mark_type} eq 'mount') {
        $mark_flags |= Linux::Fanotify::FAN_MARK_MOUNT();
    } elsif ($self->{mark_type} eq 'filesystem') {
        $mark_flags |= Linux::Fanotify::FAN_MARK_FILESYSTEM();
    }
    
    my $dirfd = -1;
    $self->{fanotify}{group}->mark($mark_flags, $self->{mask}, $dirfd, $self->{path});
    
    $self->{active} = 0;
}

sub is_active {
    my ($self) = @_;
    return $self->{active};
}

package PAL::Fanotify;

1;

=head1 EXAMPLES

=head2 Monitor File Opens

    use PAL::Fanotify;
    
    my $fan = PAL::Fanotify->new(
        flags => ['nonblock']
    );
    
    $fan->watch(
        path => '/home',
        events => ['open'],
        on_event => sub {
            my ($event) = @_;
            printf "PID %d opened: %s\n", 
                $event->{pid}, $event->{path};
        }
    );
    
    while (1) {
        $fan->poll();
        sleep 0.1;
    }

=head2 Permission Checking

    my $fan = PAL::Fanotify->new(
        class => 'content',
    );
    
    $fan->watch(
        path => '/secure',
        events => ['open_perm'],
        on_event => sub {
            my ($event) = @_;
            
            # Check if access should be allowed
            if ($event->{path} =~ /\.txt$/) {
                print "Allowing: $event->{path}\n";
                $fan->allow($event);
            } else {
                print "Denying: $event->{path}\n";
                $fan->deny($event);
            }
        }
    );
    
    while (1) {
        $fan->poll();
    }

=head2 Monitor Multiple Paths

    my $fan = PAL::Fanotify->new();
    
    for my $path ('/home', '/var/log', '/etc') {
        $fan->watch(
            path => $path,
            events => ['create', 'delete', 'modify'],
            on_event => sub {
                my ($event) = @_;
                printf "[%s] %s: %s\n",
                    $path, $event->{event}, $event->{path};
            }
        );
    }
    
    $fan->poll() while 1;

=head2 With Error Handling

    my $fan = PAL::Fanotify->new(
        on_error => sub {
            my ($error) = @_;
            warn "Fanotify error: $error\n";
        }
    );
    
    eval {
        $fan->watch(
            path => '/nonexistent',
            events => ['open'],
            on_event => sub { }
        );
    };
    if ($@) {
        die "Failed to set up watch: $@\n";
    }

=head1 ADVANTAGES OVER Linux::Fanotify

=over 4

=item * Named parameters - self-documenting code

=item * Automatic path resolution - no /proc/self/fd/ gymnastics

=item * Event names as strings - no bitwise operations

=item * Callback-based - clean event handling

=item * Automatic permission responses - allow()/deny() methods

=item * Better error messages - know what went wrong

=item * Event loop friendly - use fd() with select/poll/epoll

=back

=head1 COMPATIBILITY

Requires:

=over 4

=item * Linux kernel 2.6.37+ (basic events)

=item * Linux kernel 5.1+ (create/delete/move events)

=item * Linux::Fanotify module

=item * Root privileges (CAP_SYS_ADMIN capability)

=item * Kernel compiled with CONFIG_FANOTIFY=y

=back

=head1 SEE ALSO

L<Linux::Fanotify> - The underlying low-level module

L<Linux::Inotify2> - Alternative for file/directory watching

L<Linux::Event> - High-performance event framework

=head1 AUTHOR

Your Name <your@email.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2026 by Your Name.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
