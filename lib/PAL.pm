package PAL;

use strict;
use warnings;

our $VERSION = '0.001';

# Auto-import all PAL modules when 'use PAL;' is called
sub import {
    my $class = shift;
    my $caller = caller;
    
    # Try to load and import each PAL module
    for my $module (qw(PAL::Loop PAL::Uring PAL::Fanotify PAL::Uevent)) {
        # Skip if already loaded
        next if $INC{$module =~ s{::}{/}gr . '.pm'};
        
        eval "package $caller; use $module;";
        if ($@) {
            # Module not installed - that's ok, silently skip
            # (allows partial installs)
        }
    }
}

=head1 NAME

PAL - Perl Async for Linux

=head1 SYNOPSIS

    use PAL;  # Import all PAL modules
    
    # All modules now available:
    my $loop = PAL::Loop->new();
    my $uring = PAL::Uring->new();
    my $fan = PAL::Fanotify->new();
    my $mon = PAL::Uevent->new();

=head1 DESCRIPTION

PAL (Perl Async for Linux) is a comprehensive ecosystem of modules for modern
asynchronous programming on Linux.

Installing PAL installs all PAL modules as dependencies.

=head1 MODULES

=over 4

=item * L<PAL::Loop> - Event loop framework

=item * L<PAL::Uring> - Async I/O with io_uring

=item * L<PAL::Fanotify> - Filesystem monitoring

=item * L<PAL::Uevent> - Hardware events

=back

=head1 SEE ALSO

L<PAL::Loop>, L<PAL::Uring>, L<PAL::Fanotify>, L<PAL::Uevent>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2026.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

1;

__END__
