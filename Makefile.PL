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
        # Core dependencies for all modules
        'IO::Uring'          => '0.001',
        'Linux::Inotify2'    => '2.0',
        'Linux::Fanotify'    => '0.001',
        # Core modules (no version needed)
        'Socket'             => 0,
        'Carp'               => 0,
    },
    
    TEST_REQUIRES      => {
        'Test::More' => 0,
    },
    
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
    },
    
    dist               => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean              => { FILES => 'PAL-*' },
);
