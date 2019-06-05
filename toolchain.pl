#!/usr/bin/env perl

package main;

use strict;
use File::Basename;
use File::Spec;

use lib dirname(File::Spec->rel2abs(__FILE__));
use options;
use tarball;

options::parse_args();

my $script_dir = dirname(File::Spec->rel2abs(__FILE__));

mkdir 'dist';
mkdir 'src';
mkdir "build";
mkdir "build/$options::target-$options::libc";
$tarball::dist_dir = $script_dir . '/dist';
$tarball::src_dir = $script_dir . '/src';
my $build_dir = $script_dir . "/build/$options::target-$options::libc";

my $sysroot = "$options::destdir/$options::target/libc";

#my $mirror = 'http://mirrors.ustc.edu.cn';
my $mirror = 'http://mirrors.tuna.tsinghua.edu.cn';

my @all_uri = (
    ['binutils', '2.27',    "$mirror/gnu/binutils/binutils-2.27.tar.bz2", \&build_binutils],
    ['linux',    '4.4.179', "$mirror/kernel.org/linux/kernel/v4.x/linux-4.4.179.tar.xz", \&build_linux],
    ['gmp',      '6.1.2',   "$mirror/gnu/gmp/gmp-6.1.2.tar.xz"],
    ['mpfr',     '3.1.4',   "$mirror/gnu/mpfr/mpfr-3.1.4.tar.xz"],
    ['mpc',      '1.0.3',   "$mirror/gnu/mpc/mpc-1.0.3.tar.gz"],
    ['gcc',      '6.3.0',   "$mirror/gnu/gcc/gcc-6.3.0/gcc-6.3.0.tar.bz2", \&build_gcc],
);

if ($options::libc eq 'glibc') {
    push @all_uri, ['glibc',
                    '2.23',
                    "$mirror/gnu/glibc/glibc-2.23.tar.xz",
                    \&build_glibc];
} elsif ($options::libc eq 'musl') {
    push @all_uri, ['musl',
                    '1.1.22',
                    "https://www.musl-libc.org/releases/musl-1.1.22.tar.gz",
                    \&build_musl];
} else {
    die "un-support libc implementation.";
}

foreach my $item (@all_uri) {
    my $name = $item->[0];
    my $version = $item->[1];
    my $uri = $item->[2];
    my $handler = $item->[3];

    fetch_and_extract($uri);
    if ($handler) {
        mkdir "$build_dir/$name-$version";
        $handler->("$tarball::src_dir/$name-$version",
                   "$build_dir/$name-$version");
    }
}

sub build_binutils {
    my $src = shift;
    my $build = shift;
    return if -e "$build/.installed";

    my $config_cmd = "cd $build; $src/configure ".
        "--prefix=$options::destdir ".
        "--with-sysroot=$sysroot ".
        "--target=$options::target ".
        "--disable-multilib";
    my $make_cmd = "cd $build; ".
        "make -j$options::jobs && ".
        "make install && ".
        "touch .installed";

    die "configure failed" if system($config_cmd);
    die "make failed" if system($make_cmd);
}

sub build_linux {
    my $src = shift;
    my $build = shift;
    return if -e "$build/.installed";

    my $inner_arch = $options::arch;
    $inner_arch = 'x86' if $inner_arch eq 'i686';
    $inner_arch = 'arm64' if $inner_arch eq 'aarch64';
    my $make_cmd = "cd $src; ".
        "make ARCH=$inner_arch INSTALL_HDR_PATH=$sysroot/usr ".
        "headers_install && touch .installed";

    die "make failed" if system($make_cmd);
}

sub build_gcc {
    my $src = shift;
    my $build = shift;
    return if -e "$build/.installed-gcc-compilers";

    for (my $i = 2; $i < 5; $i++) {
        my $name = $all_uri[$i]->[0];
        my $version = $all_uri[$i]->[1];
        system("ln -sf ../$name-$version $src/$name");
        #system("cp -a $build/../$name-$version $build/$name");
    }

    my $config_cmd = "cd $build; $src/configure ".
        "--prefix=$options::destdir ".
        "--target=$options::target ".
        "--with-sysroot=$sysroot ".
        "--with-gnu-as ".
        "--with-gnu-ld ".
        "--disable-multilib ".
        "--disable-nls ".
        "--disable-libmudflap ".
        "--disable-libsanitizer ".
        "--without-isl ".
        "--without-cloog ".
        "--enable-lto ".
        "--enable-shared ".
        "--enable-threads ".
        "--enable-languages=c,c++";
    my $make_cmd = "cd $build; ".
        "make -j$options::jobs all-gcc && ".
        "make install-gcc && ".
        "touch .installed-gcc-compilers";
    die "configure failed" if system($config_cmd);
    die "make failed" if system($make_cmd);
}

sub build_libgcc {
    my $build = "$build_dir/$all_uri[5]->[0]-$all_uri[5]->[1]";
    return if -e "$build/.installed-libgcc";

    my $make_cmd = "cd $build; ".
        "make -j$options::jobs all-target-libgcc && ".
        "make install-target-libgcc && ".
        "touch .installed-libgcc";
    die "make failed" if system($make_cmd);
}

sub build_all_gcc {
    my $build = "$build_dir/$all_uri[5]->[0]-$all_uri[5]->[1]";
    return if -e "$build/.installed";

    #$ENV{C_INCLUDE_PATH} = "$options::destdir/$options::target/include";
    #$ENV{CPLUS_INCLUDE_PATH} = "$options::destdir/$options::target/include";
    #$ENV{LD_LIBRARY_PATH} = "$options::destdir/$options::target/lib";
    #$ENV{PKG_CONFIG_PATH} = "$options::destdir/$options::target/lib/pkgconfig";

    my $make_cmd = "cd $build; ".
        "make -j$options::jobs && ".
        "make install && ".
        "touch .installed";
    die "make failed" if system($make_cmd);

    my $src = "src/$all_uri[5]->[0]-$all_uri[5]->[1]";
    my $limits_hdr = `find _install/ -name 'limits.h' |grep 'include-fixed' |xargs readlink -f`;
    system("cd $src/gcc; cat limitx.h glimits.h limity.h > $limits_hdr");
}

sub build_glibc {
    my $src = shift;
    my $build = shift;

    if (! -e "$build/.installed-glibc-headers") {
        my $install_root = "$sysroot/usr";
        # libc_cv_ssp is to resolv __stack_chk_gurad for x86_64
        my $config_cmd = "cd $build; $src/configure ".
            "--prefix=/usr ".
            "--host=$options::target ".
            "--disable-multilib --without-selinux ".
            "--with-headers=$install_root/include ".
            "libc_cv_forced_unwind=yes ".
            "libc_cv_ssp=no ".
            "libc_cv_ssp_strong=no";
        my $make_cmd = "cd $build; ".
            "make install-bootstrap-headers=yes ".
            "install-headers install_root=$sysroot && ".
            "touch $install_root/include/gnu/stubs.h && ".
            "make -j$options::jobs csu/subdir_lib && ".
            "mkdir -p $install_root/lib && ".
            "install csu/crt1.o csu/crti.o csu/crtn.o $install_root/lib && ".
            "$options::target-gcc -nostdlib -nostartfiles -shared ".
            "-x c /dev/null -o $install_root/lib/libc.so && ".
            "touch .installed-glibc-headers";

        die "configure failed" if system($config_cmd);
        die "make failed" if system($make_cmd);
    }

    build_libgcc();

    if (! -e "$build/.installed") {
        # all glibc
        my $make_cmd = "cd $build; ".
            "make -j$options::jobs && ".
            "make install install_root=$sysroot && ".
            "touch .installed";
        die "make failed" if system($make_cmd);
    }

    build_all_gcc();
}

sub build_musl {
    my $src = shift;
    my $build = shift;

    if (! -e "$build/.installed-headers") {
        my $install_root = "$sysroot/usr";
        my $config_cmd = "cd $build; $src/configure ".
            "--prefix=/usr ".
            "--host=$options::target";
        my $make_cmd = "cd $build;";
        my $make_cmd = "cd $build; ".
            "make install-headers DESTDIR=$sysroot && ".
            "mkdir -p $install_root/include/gnu && ".
            "touch $install_root/include/gnu/stubs.h && ".
            "make -j$options::jobs; ".
            "mkdir -p $install_root/lib && ".
            "install lib/crt1.o lib/crti.o lib/crtn.o $install_root/lib && ".
            "$options::target-gcc -nostdlib -nostartfiles -shared ".
            "-x c /dev/null -o $install_root/lib/libc.so && ".
            "touch .installed-headers";

        die "configure failed" if system($config_cmd);
        die "make failed" if system($make_cmd);
    }

    build_libgcc();

    if (! -e "$build/.installed") {
        my $config_cmd = "cd $build; $src/configure ".
            "--prefix=/usr ".
            "--host=$options::target";
        my $make_cmd = "cd $build; ".
            "make clean && ".
            "make -j$options::jobs && ".
            "make install DESTDIR=$sysroot && ".
            "touch .installed";
        die "configure failed" if system($config_cmd);
        die "make failed" if system($make_cmd);
    }

    build_all_gcc();
}
