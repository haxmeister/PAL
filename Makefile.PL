use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME               => 'PAL',
    AUTHOR             => 'PAL Project',
    VERSION            => '0.001',
    ABSTRACT           => 'Perl Async for Linux - Complete async framework',
    LICENSE            => 'perl_5',
    MIN_PERL_VERSION   => '5.008',
    
    PREREQ_PM          => {
        # Core Perl modules
        'Socket'             => 0,
        'Carp'               => 0,
        'Scalar::Util'       => 0,
        'Time::HiRes'        => 0,
        'Time::Spec'         => 0,
    },
    
    # Optional but recommended XS modules
    # Users can install with: cpanm --installdeps .
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => '6.64',
    },
    
    # Make XS dependencies recommended (not required)
    # This allows installation without them, but cpanm --installdeps will try
    META_MERGE         => {
        'meta-spec' => { version => 2 },
        resources   => {
            repository => {
                type => 'git',
                url  => 'https://github.com/haxmeister/pal.git',
                web  => 'https://github.com/haxmeister/pal',
            },
            bugtracker => {
                web => 'https://github.com/haxmeister/pal/issues',
            },
        },
        keywords => [
            'pal', 'perl', 'async', 'linux', 'event-loop',
            'io_uring', 'async-io', 'fanotify', 'uevent', 'netlink',
        ],
        prereqs => {
            runtime => {
                recommends => {
                    'IO::Uring'          => 0,      # Any version
                    'Linux::Fanotify'    => '1.2',  # Version 1.2.0 exists
                    'Linux::Inotify2'    => 0,      # Any version
                },
            },
        },
    },
    
    TEST_REQUIRES      => {
        'Test::More' => 0,
    },
    
    dist               => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean              => { FILES => 'PAL-*' },
);

print STDERR "\n";
print STDERR "=" x 70 . "\n";
print STDERR "PAL installed successfully!\n";
print STDERR "\n";
print STDERR "Recommended XS dependencies for full functionality:\n";
print STDERR "  - IO::Uring (for PAL::Uring and PAL::Loop async I/O)\n";
print STDERR "  - Linux::Fanotify 1.2+ (for PAL::Fanotify)\n";
print STDERR "  - Linux::Inotify2 (for PAL::Loop file watching)\n";
print STDERR "\n";
print STDERR "PAL::Uevent has zero dependencies and works immediately!\n";
print STDERR "\n";
print STDERR "To install recommended dependencies:\n";
print STDERR "  cpanm --installdeps .\n";
print STDERR "=" x 70 . "\n";
print STDERR "\n";
