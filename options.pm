package options;

use strict;
use Getopt::Long;
Getopt::Long::Configure("bundling");
use File::Basename;
use Cwd;

our $help = 0;
our $verbose = 0;
our $arch = 'arm';
our $libc = "glibc";
our $destdir = "";
our $target = "";
our $jobs = 1;

sub usage {
    print "Usage: " . basename($0) . " [options]\n";
    print "  --help|-h         display this page\n";
    print "  --verbose         verbose mode \n";
    print "  --arch <arg>      arm | aarch64 | x86_64 [default: arm]\n";
    print "  --libc <arg>      glibc | musl [default: glibc]\n";
    print "  --destdir <arg>   where to install the toolchain [default: ./_install/arm-glibc]\n";
    print "  --jobs|-j <arg>   pass to make\n";
}

sub parse_args() {
    GetOptions(
        'help|h' => \$help,
        'verbose|v' => \$verbose,
        'arch=s' => \$arch,
        'libc=s' => \$libc,
        'destdir=s' => \$destdir,
        'jobs|j=i' => \$jobs,
    ) or die $!;

    if ($help) {
        usage() && exit 0;
    }

    if ($arch eq 'x86_64') {
        $target = "${arch}-unknown-linux";
    } else {
        $target = "${arch}-linux";
    }

    if ($libc eq 'glibc') {
        $target = "${target}-gnu";
        if ($arch eq 'arm') {
            $target = "${target}eabi";
        }
    } elsif ($libc eq 'musl') {
        $target = "${target}-musl";
    }

    if ($jobs < 1) {
        $jobs = 1;
    }

    if ($destdir eq "") {
        $destdir = getcwd . "/_install/$arch-$libc";
    }
    $ENV{PATH} = "$ENV{PATH}:$destdir/bin";

    if ($verbose) {
        print "help: $help\n";
        print "verbose: $verbose\n";
        print "arch: $arch\n";
        print "libc: $libc\n";
        print "destdir: $destdir\n";
        print "target: $target\n";
        print "jobs: $jobs\n";
        print "PATH=$ENV{PATH}\n";
    }
}

1;
