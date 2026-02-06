![CI](https://github.com/haxmeister/PAL/workflows/CI/badge.svg)
# PAL - Perl Async for Linux

Modern asynchronous programming framework for Perl on Linux.

---

## Installation

```bash
cpanm PAL
```

This single command installs the complete PAL framework with all modules:
- **PAL::Loop** - Event loop framework
- **PAL::Uring** - Async I/O with io_uring
- **PAL::Fanotify** - Filesystem monitoring
- **PAL::Uevent** - Hardware event monitoring

---

## Quick Start

```perl
use PAL;  # Imports all modules

# Event loop
my $loop = PAL::Loop->new();
$loop->timer(after => 5, cb => sub { print "Done!\n" });
$loop->run();

# Async I/O
my $uring = PAL::Uring->new();
$uring->read_file('data.txt', sub { my ($data) = @_; print $data; });

# Filesystem monitoring
my $fan = PAL::Fanotify->new();
$fan->watch(path => '/secure', events => ['open'], on_event => sub { ... });

# Hardware events
my $mon = PAL::Uevent->new();
$mon->watch(subsystem => 'usb', on_event => sub { ... });
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      PAL::Loop                          │
│              (Unified Event Loop)                       │
│  ┌──────────┬──────────┬──────────┬──────────────────┐ │
│  │  Timers  │    I/O   │ Signals  │   Filesystem     │ │
│  └──────────┴──────────┴──────────┴──────────────────┘ │
└────┬─────────────────┬────────────────────┬────────────┘
     │                 │                    │
┌────▼─────┐     ┌─────▼────────┐    ┌─────▼──────────┐
│ PAL::    │     │ PAL::        │    │ PAL::          │
│ Uring    │     │ Fanotify     │    │ Uevent         │
│ (Async   │     │ (Filesystem  │    │ (Hardware      │
│  I/O)    │     │  Monitoring) │    │  Events)       │
└──────────┘     └──────────────┘    └────────────────┘
     │                 │                    │
┌────▼─────────────────▼────────────────────▼────────────┐
│            Linux Kernel Interfaces                      │
│   io_uring          fanotify          netlink/uevent   │
└─────────────────────────────────────────────────────────┘
```

---

## Modules

### PAL::Loop - Event Loop Framework

Unified event loop built on io_uring with timers, I/O, signals, and monitoring.

```perl
my $loop = PAL::Loop->new();
$loop->timer(after => 5, cb => sub { ... });
$loop->io(fh => $socket, poll => 'r', cb => sub { ... });
$loop->run();
```

### PAL::Uring - Async I/O

High-performance async I/O using io_uring with zero-copy operations.

```perl
my $uring = PAL::Uring->new();
$uring->read_file('data.txt', sub { my ($data, $err) = @_; ... });
$uring->wait();
```

### PAL::Fanotify - Filesystem Monitoring

Advanced filesystem monitoring with permission enforcement.

```perl
my $fan = PAL::Fanotify->new();
$fan->watch(
    path => '/secure',
    events => ['open', 'perm'],
    on_event => sub { my ($event) = @_; ... }
);
```

### PAL::Uevent - Hardware Events

Monitor kernel hardware events for USB, network, disk, and power.

```perl
my $mon = PAL::Uevent->new();
$mon->watch(
    subsystem => 'usb',
    on_event => sub { my ($event) = @_; ... }
);
$mon->poll();
```

---

## Features

- ✅ **Modern Linux** - Built on io_uring, fanotify, netlink
- ✅ **High Performance** - Zero-copy I/O, batch operations
- ✅ **Simple API** - Clean, consistent interfaces
- ✅ **Well Documented** - Comprehensive POD docs
- ✅ **Production Ready** - Battle-tested code

---

## Requirements

- Linux 5.1+ (for io_uring support)
- Perl 5.8+

Individual features may require:
- io_uring: Linux 5.1+
- fanotify: Linux 2.6.37+
- uevent: Linux 2.6.10+

---

## Documentation

```bash
perldoc PAL::Loop
perldoc PAL::Uring
perldoc PAL::Fanotify
perldoc PAL::Uevent
```

---

## Philosophy

PAL is designed to:

1. **Leverage Modern Linux** - Use latest kernel features for maximum performance
2. **Keep It Simple** - Clean APIs that are easy to understand and use
3. **Stay Composable** - Modules work independently or together seamlessly
4. **Document Everything** - Every feature has examples and clear documentation

---

## Why PAL?

### vs Other Event Loops

- **IO::Async** - Great framework, but doesn't use io_uring
- **Mojo::IOLoop** - Excellent for web, but limited Linux integration
- **AnyEvent** - Abstract, but backends don't leverage modern Linux
- **PAL** - Built specifically for Linux with modern kernel features

### vs Other Languages

- **Python asyncio** - No fanotify/uevent access
- **Node.js libuv** - No fanotify support
- **Go** - Has syscall package, but no high-level wrappers
- **PAL** - Comprehensive Linux async ecosystem for Perl

---

## License

This software is copyright (c) 2026.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

---

## Repository

https://github.com/haxmeister/pal
