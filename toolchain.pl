#!/usr/bin/env perl

package main;

#use strict;
use File::Basename;
use File::Spec;

my $script_dir = dirname(File::Spec->rel2abs(__FILE__));
BEGIN {push(@INC, "$script_dir");}

use options;
use tarball;

options::parse_args();

mkdir 'dist';
mkdir 'src';
mkdir "build";
mkdir "build/target-$options::target";
$tarball::dist_dir = $script_dir . '/dist';
$tarball::src_dir = $script_dir . '/src';
my $build_dir = $script_dir . "/build/target-$options::target";

my $mirror = 'http://mirrors.ustc.edu.cn';

my @all_uri = (
    ['binutils', '2.27',    "$mirror/gnu/binutils/binutils-2.27.tar.bz2", \&build_binutils],
    ['linux',    '4.4.179', "$mirror/kernel.org/linux/kernel/v4.x/linux-4.4.179.tar.xz", \&build_linux],
    ['gmp',      '6.1.2',   "$mirror/gnu/gmp/gmp-6.1.2.tar.xz"],
    ['mpfr',     '3.1.4',   "$mirror/gnu/mpfr/mpfr-3.1.4.tar.xz"],
    ['mpc',      '1.0.3',   "$mirror/gnu/mpc/mpc-1.0.3.tar.gz"],
    ['isl',      '0.14',    "http://isl.gforge.inria.fr/isl-0.14.tar.xz"],
    ['cloog',    '0.18.4',  "http://www.bastoul.net/cloog/pages/download/cloog-0.18.4.tar.gz"],
    ['gcc',      '6.3.0',   "$mirror/gnu/gcc/gcc-6.3.0/gcc-6.3.0.tar.bz2", \&build_gcc],
    ['glibc',    '2.23',    "$mirror/gnu/glibc/glibc-2.23.tar.xz", \&build_glibc],
);

foreach my $item (@all_uri) {
    my $name = $item->[0];
    my $version = $item->[1];
    my $uri = $item->[2];
    my $handler = $item->[3];

    fetch_and_extract($uri);
    if ($handler) {
        mkdir "$build_dir/$name-$version";
        $handler->("$tarball::src_dir/$name-$version", "$build_dir/$name-$version");
    }
}

sub build_binutils {
    my $src = shift;
    my $build = shift;
    return if -e "$build/.installed";

    my $config_cmd = "cd $build; $src/configure --prefix=$options::destdir --target=$options::target --disable-multilib";
    my $make_cmd = "cd $build; make -j$options::jobs && make install && touch .installed";

    die "configure failed" if system($config_cmd);
    die "make failed" if system($make_cmd);
}

sub build_linux {
    my $src = shift;
    my $build = shift;
    return if -e "$build/.installed";

    my $inner_arch = $options::arch;
    $inner_arch = 'x86' if $inner_arch eq 'i686';
    my $make_cmd = "cd $src; make ARCH=$inner_arch INSTALL_HDR_PATH=$options::destdir/$options::target headers_install && touch .installed";

    die "make failed" if system($make_cmd);
}

sub build_gcc {
    my $src = shift;
    my $build = shift;
    return if -e "$build/.installed-gcc-compilers";

    for (my $i = 2; $i < 7; $i++) {
        my $name = $all_uri[$i]->[0];
        my $version = $all_uri[$i]->[1];
        system("ln -sf ../$name-$version $src/$name");
        #system("cp -a $build/../$name-$version $build/$name");
    }

    my $config_cmd = "cd $build; $src/configure --prefix=$options::destdir --target=$options::target --enable-languages=c,c++ --disable-multilib";
    my $make_cmd = "cd $build; make -j$options::jobs all-gcc && make install-gcc && touch .installed-gcc-compilers";
    die "configure failed" if system($config_cmd);
    die "make failed" if system($make_cmd);
}

sub build_libgcc {
    my $build = "$build_dir/$all_uri[7]->[0]-$all_uri[7]->[1]";
    return if -e "$build/.installed-libgcc";

    my $make_cmd = "cd $build; make -j$options::jobs all-target-libgcc && make install-target-libgcc && touch .installed-libgcc";
    die "make failed" if system($make_cmd);
}

sub build_all_gcc {
    my $build = "$build_dir/$all_uri[7]->[0]-$all_uri[7]->[1]";
    return if -e "$build/.installed";

    #$ENV{C_INCLUDE_PATH} = "$options::destdir/$options::target/include";
    #$ENV{CPLUS_INCLUDE_PATH} = "$options::destdir/$options::target/include";
    #$ENV{LD_LIBRARY_PATH} = "$options::destdir/$options::target/lib";
    #$ENV{PKG_CONFIG_PATH} = "$options::destdir/$options::target/lib/pkgconfig";

    my $make_cmd = "cd $build; make -j$options::jobs && make install && touch .installed";
    die "make failed" if system($make_cmd);

    my $src = "src/$all_uri[7]->[0]-$all_uri[7]->[1]";
    my $limits_hdr = `find _install/ -name 'limits.h' |grep 'include-fixed' |xargs readlink -f`;
    system("cd $src/gcc; cat limitx.h glimits.h limity.h > $limits_hdr");
}

sub build_glibc {
    my $src = shift;
    my $build = shift;
    my $install_root = "$options::destdir/$options::target";

    if (! -e "$build/.installed-glibc-headers") {
        # libc_cv_ssp is to resolv __stack_chk_gurad for x86_64
        my $config_cmd = "cd $build; $src/configure --prefix=$install_root --host=$options::target --disable-multilib --without-selinux ".
        "--with-headers=$install_root/include libc_cv_forced_unwind=yes libc_cv_ssp=no libc_cv_ssp_strong=no";
        my $make_cmd = "cd $build; make install-bootstrap-headers=yes install-headers && touch $install_root/include/gnu/stubs.h && ".
        "make -j$options::jobs csu/subdir_lib && install csu/crt1.o csu/crti.o csu/crtn.o $install_root/lib && ".
        "$options::target-gcc -nostdlib -nostartfiles -shared -x c /dev/null -o $install_root/lib/libc.so && ".
        "touch .installed-glibc-headers";

        die "configure failed" if system($config_cmd);
        die "make failed" if system($make_cmd);
    }

    build_libgcc();

    if (! -e "$build/.installed") {
        # all glibc
        my $make_cmd = "cd $build; make -j$options::jobs && make install && touch .installed";
        die "make failed" if system($make_cmd);
    }

    build_all_gcc();

    $build = $build . "-rootfs";
    if (! -e "$build/.installed") {
        mkdir $build;
        # libc_cv_ssp is to resolv __stack_chk_gurad for x86_64
        $config_cmd = "cd $build; $src/configure --prefix=/usr --host=$options::target --disable-multilib --without-selinux ".
        "--with-headers=$install_root/include libc_cv_forced_unwind=yes libc_cv_ssp=no libc_cv_ssp_strong=no";
        $make_cmd = "cd $build; make -j$options::jobs && make install install_root=$install_root/libc && touch .installed";

        die "configure failed" if system($config_cmd);
        die "make failed" if system($make_cmd);
        system("cd $install_root/libc/lib; sed -i 's#/lib/##g' libc.so libm.so libpthread.so");

        system("cp -a $install_root/libc/* $install_root/ && rm -rf $install_root/libc");
    }
}
