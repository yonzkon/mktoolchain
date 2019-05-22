package options;

use strict;
use Getopt::Long;
Getopt::Long::Configure("bundling");
use File::Basename;
use Cwd;

our $help = 0;
our $verbose = 0;
our $arch = 'arm';
our $destdir = "";
our $target = "";
our $jobs = 1;

sub usage {
    print "Usage: " . basename($0) . " [options]\n";
    print "  --help|-h         display this page\n";
    print "  --verbose         verbose mode \n";
    print "  --arch <arg>      arm | i686 | x86_64 | ...\n";
    print "  --destdir <arg>   where to install the toolchain\n";
    print "  --jobs <arg>      pass to make\n";
}

sub parse_args() {
    GetOptions(
        'help|h' => \$help,
        'verbose|v' => \$verbose,
        'arch=s' => \$arch,
        'destdir=s' => \$destdir,
        'jobs|j=i' => \$jobs,
    ) or die $!;

    if ($help) {
        usage() && exit 0;
    }

    $target = "${arch}-unknown-linux-gnu";
    if ($arch eq 'arm') {
        $target = "${target}eabi";
    }

    if ($jobs < 1) {
        $jobs = 1;
    }

    if ($destdir eq "") {
        $destdir = getcwd . "/_install/$arch";
    }
    $ENV{PATH} = "$ENV{PATH}:$destdir/bin";

    if ($verbose) {
        print "help: $help\n";
        print "verbose: $verbose\n";
        print "arch: $arch\n";
        print "destdir: $destdir\n";
        print "target: $target\n";
        print "jobs: $jobs\n";
        print "PATH=$ENV{PATH}\n";
    }
}

1;
