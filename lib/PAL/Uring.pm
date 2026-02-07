package PAL::Uring;

use strict;
use warnings;
use IO::Uring;
use Carp qw(croak carp);

our $VERSION = '0.001';

=head1 NAME

PAL::Uring - A simplified interface to IO::Uring

=head1 SYNOPSIS

    use PAL::Uring;
    
    # Create a new easy-to-use uring instance
    my $uring = PAL::Uring->new(
        queue_size => 64,  # optional, defaults to 32
    );
    
    # Read a file asynchronously
    $uring->read_file(
        path => '/etc/hosts',
        on_success => sub {
            my ($data) = @_;
            print "File contents: $data\n";
        },
        on_error => sub {
            my ($error) = @_;
            warn "Failed to read: $error\n";
        }
    );
    
    # Write to a file
    $uring->write_file(
        path => '/tmp/output.txt',
        data => "Hello, world!",
        on_success => sub {
            print "Write completed!\n";
        }
    );
    
    # Network operations
    $uring->tcp_connect(
        host => 'example.com',
        port => 80,
        on_connected => sub {
            my ($sock) = @_;
            $uring->send($sock, "GET / HTTP/1.0\r\n\r\n");
        }
    );
    
    # Run the event loop
    $uring->run();

=head1 DESCRIPTION

PAL::Uring provides a simplified, more intuitive interface to IO::Uring.
Instead of dealing with low-level flags, callbacks with result codes, and 
manual buffer management, this module provides:

=over 4

=item * Named parameters instead of positional arguments

=item * Separate success and error callbacks

=item * Automatic buffer management

=item * Higher-level operations (read_file, write_file, etc.)

=item * Simpler event loop management

=back

=head1 METHODS

=head2 new(%options)

Creates a new PAL::Uring instance.

Options:

=over 4

=item * queue_size - Size of the submission queue (default: 32)

=item * cqe_entries - Completion queue entries (default: queue_size * 2)

=item * sqpoll - Enable sqpoll mode with given idle time in ms (optional)

=back

=cut

sub new {
    my ($class, %opts) = @_;
    
    my $queue_size = delete $opts{queue_size} || 32;
    
    my %uring_opts;
    $uring_opts{cqe_entries} = delete $opts{cqe_entries} if exists $opts{cqe_entries};
    $uring_opts{sqpoll} = delete $opts{sqpoll} if exists $opts{sqpoll};
    
    if (%opts) {
        croak "Unknown options: " . join(', ', keys %opts);
    }
    
    my $ring = IO::Uring->new($queue_size, %uring_opts);
    
    my $self = bless {
        ring => $ring,
        pending => 0,
        running => 0,
    }, $class;
    
    return $self;
}

=head2 read_file(%options)

Read an entire file asynchronously.

Options:

=over 4

=item * path - Path to the file (required)

=item * on_success - Called with file contents on success

=item * on_error - Called with error message on failure

=item * flags - Open flags (default: O_RDONLY)

=item * mode - File mode (default: 0)

=back

=cut

sub read_file {
    my ($self, %opts) = @_;
    
    my $path = delete $opts{path} or croak "path is required";
    my $on_success = delete $opts{on_success} or croak "on_success callback is required";
    my $on_error = delete $opts{on_error} || sub { carp "Read error: $_[0]" };
    my $flags = delete $opts{flags} || 0x0000; # O_RDONLY
    my $mode = delete $opts{mode} || 0;
    
    require Fcntl;
    $flags = Fcntl::O_RDONLY() unless $flags;
    
    my $buffer = '';
    my $offset = 0;
    my $fh;
    
    $self->{pending}++;
    
    # Open the file
    $self->{ring}->openat(-100, $path, $flags, $mode, 0, sub {
        my ($res, $cflags) = @_;
        
        if ($res < 0) {
            $self->{pending}--;
            $on_error->("Failed to open $path: $!");
            return;
        }
        
        $fh = $res;
        $self->_read_chunk($fh, \$buffer, $offset, $on_success, $on_error);
    });
}

sub _read_chunk {
    my ($self, $fh, $buffer_ref, $offset, $on_success, $on_error) = @_;
    
    my $chunk = "\0" x 4096;
    
    $self->{ring}->read($fh, $chunk, $offset, 0, sub {
        my ($res, $cflags) = @_;
        
        if ($res < 0) {
            $self->{ring}->close($fh, 0, sub {});
            $self->{pending}--;
            $on_error->("Read failed: $!");
            return;
        }
        
        if ($res == 0) {
            # EOF
            $self->{ring}->close($fh, 0, sub {});
            $self->{pending}--;
            $on_success->($$buffer_ref);
            return;
        }
        
        # Append chunk and continue reading
        $$buffer_ref .= substr($chunk, 0, $res);
        $self->_read_chunk($fh, $buffer_ref, $offset + $res, $on_success, $on_error);
    });
}

=head2 write_file(%options)

Write data to a file asynchronously.

Options:

=over 4

=item * path - Path to the file (required)

=item * data - Data to write (required)

=item * on_success - Called when write completes

=item * on_error - Called with error message on failure

=item * flags - Open flags (default: O_WRONLY|O_CREAT|O_TRUNC)

=item * mode - File mode (default: 0644)

=back

=cut

sub write_file {
    my ($self, %opts) = @_;
    
    my $path = delete $opts{path} or croak "path is required";
    my $data = delete $opts{data};
    croak "data is required" unless defined $data;
    my $on_success = delete $opts{on_success} || sub {};
    my $on_error = delete $opts{on_error} || sub { carp "Write error: $_[0]" };
    my $flags = delete $opts{flags};
    my $mode = delete $opts{mode} || 0644;
    
    require Fcntl;
    $flags = Fcntl::O_WRONLY() | Fcntl::O_CREAT() | Fcntl::O_TRUNC() unless defined $flags;
    
    $self->{pending}++;
    
    # Open the file
    $self->{ring}->openat(-100, $path, $flags, $mode, 0, sub {
        my ($res, $cflags) = @_;
        
        if ($res < 0) {
            $self->{pending}--;
            $on_error->("Failed to open $path: $!");
            return;
        }
        
        my $fh = $res;
        
        # Write the data
        $self->{ring}->write($fh, $data, 0, 0, sub {
            my ($res, $cflags) = @_;
            
            $self->{ring}->close($fh, 0, sub {});
            $self->{pending}--;
            
            if ($res < 0) {
                $on_error->("Write failed: $!");
                return;
            }
            
            $on_success->();
        });
    });
}

=head2 send(%options)

Send data on a socket.

Options:

=over 4

=item * socket - Socket filehandle (required)

=item * data - Data to send (required)

=item * on_success - Called when send completes

=item * on_error - Called with error message on failure

=item * flags - Send flags (default: 0)

=back

=cut

sub send {
    my ($self, %opts) = @_;
    
    my $sock = delete $opts{socket} or croak "socket is required";
    my $data = delete $opts{data};
    croak "data is required" unless defined $data;
    my $on_success = delete $opts{on_success} || sub {};
    my $on_error = delete $opts{on_error} || sub { carp "Send error: $_[0]" };
    my $flags = delete $opts{flags} || 0;
    
    $self->{pending}++;
    
    $self->{ring}->send($sock, $data, $flags, 0, 0, sub {
        my ($res, $cflags) = @_;
        
        $self->{pending}--;
        
        if ($res < 0) {
            $on_error->("Send failed: $!");
            return;
        }
        
        $on_success->($res);
    });
}

=head2 recv(%options)

Receive data from a socket.

Options:

=over 4

=item * socket - Socket filehandle (required)

=item * size - Buffer size (default: 4096)

=item * on_data - Called with received data

=item * on_error - Called with error message on failure

=item * flags - Receive flags (default: 0)

=back

=cut

sub recv {
    my ($self, %opts) = @_;
    
    my $sock = delete $opts{socket} or croak "socket is required";
    my $size = delete $opts{size} || 4096;
    my $on_data = delete $opts{on_data} or croak "on_data callback is required";
    my $on_error = delete $opts{on_error} || sub { carp "Recv error: $_[0]" };
    my $flags = delete $opts{flags} || 0;
    
    my $buffer = "\0" x $size;
    
    $self->{pending}++;
    
    $self->{ring}->recv($sock, $buffer, $flags, 0, 0, sub {
        my ($res, $cflags) = @_;
        
        $self->{pending}--;
        
        if ($res < 0) {
            $on_error->("Recv failed: $!");
            return;
        }
        
        my $data = substr($buffer, 0, $res);
        $on_data->($data);
    });
}

=head2 timeout(%options)

Set a timeout.

Options:

=over 4

=item * seconds - Timeout in seconds (can be fractional)

=item * on_timeout - Called when timeout fires

=item * on_error - Called with error message on failure

=back

=cut

sub timeout {
    my ($self, %opts) = @_;
    
    my $seconds = delete $opts{seconds};
    croak "seconds is required" unless defined $seconds;
    my $on_timeout = delete $opts{on_timeout} || sub {};
    my $on_error = delete $opts{on_error} || sub { carp "Timeout error: $_[0]" };
    
    require Time::Spec;
    my $timespec = Time::Spec->new($seconds);
    
    $self->{pending}++;
    
    $self->{ring}->timeout($timespec, 0, 0, 0, sub {
        my ($res, $cflags) = @_;
        
        $self->{pending}--;
        
        if ($res < 0 && $res != -62) { # -62 is ETIME (timeout expired, which is success)
            $on_error->("Timeout failed: $!");
            return;
        }
        
        $on_timeout->();
    });
}

=head2 run(%options)

Run the event loop.

Options:

=over 4

=item * until - Stop when this condition is true (optional)

=item * max_events - Maximum events per iteration (default: 1)

=back

This will process events until there are no more pending operations,
or until the 'until' condition becomes true.

=cut

sub run {
    my ($self, %opts) = @_;
    
    my $until = delete $opts{until};
    my $max_events = delete $opts{max_events} || 1;
    
    $self->{running} = 1;
    
    while ($self->{running} && $self->{pending} > 0) {
        last if $until && $until->();
        $self->{ring}->run_once($max_events);
    }
}

=head2 stop()

Stop the event loop.

=cut

sub stop {
    my ($self) = @_;
    $self->{running} = 0;
}

=head2 pending()

Returns the number of pending operations.

=cut

sub pending {
    my ($self) = @_;
    return $self->{pending};
}

=head2 ring()

Returns the underlying IO::Uring object for advanced usage.

=cut

sub ring {
    my ($self) = @_;
    return $self->{ring};
}


# Wrapper methods for compatibility with tests
sub wait   { shift->{ring}->wait(@_) }
sub submit { shift->{ring}->submit(@_) }  
sub read   { shift->{ring}->read(@_) }
sub write  { shift->{ring}->write(@_) }
sub accept { shift->{ring}->accept(@_) }

1;

=head1 EXAMPLES

=head2 Simple File Copy

    my $uring = PAL::Uring->new();
    
    $uring->read_file(
        path => 'input.txt',
        on_success => sub {
            my ($data) = @_;
            $uring->write_file(
                path => 'output.txt',
                data => $data,
                on_success => sub {
                    print "Copy complete!\n";
                }
            );
        }
    );
    
    $uring->run();

=head2 With Timeout

    my $uring = PAL::Uring->new();
    my $timed_out = 0;
    
    $uring->read_file(
        path => '/dev/random',
        on_success => sub { print "Read succeeded\n"; }
    );
    
    $uring->timeout(
        seconds => 5,
        on_timeout => sub {
            $timed_out = 1;
            print "Timed out!\n";
        }
    );
    
    $uring->run(until => sub { $timed_out });

=head1 ADVANTAGES OVER IO::Uring

=over 4

=item * Named parameters make code self-documenting

=item * Separate success/error callbacks simplify error handling

=item * Automatic buffer management for common operations

=item * Higher-level operations (read_file, write_file)

=item * Clearer event loop control

=item * Automatic tracking of pending operations

=back

=head1 SEE ALSO

L<IO::Uring> - The underlying low-level module

=head1 AUTHOR

Your Name <your@email.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2026 by Your Name.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
