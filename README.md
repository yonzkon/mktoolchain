# mktoolchain

[![Build Status](https://travis-ci.com/yonzkon/toolchain-make.svg?branch=master)](https://travis-ci.com/yonzkon/toolchain-make)

Make cross toolchains.

## Supported architectures

- arm
- aarch64

## Usage

### mktoolchain.sh
```
Usage: mktoolchian.sh {ARCH} {COMMAND} [PREFIX, [WORKSPACE]]

  {ARCH}    arm | i686 | x86_64 | ...
  {COMMAND} binutils
            linux_uapi_headers
            gcc_compilers
            glibc_headers_and_startup_files
            gcc_libgcc
            glibc
            gcc
            rootfs_busybox
            rootfs_glibc
            rootfs_readline
            rootfs_ncurses
            rootfs_gdb
            rootfs_binutils
            rootfs_make
            rootfs_bash
            simplify_rootfs

  [PREFIX]  where to install the toolchain [default: $(pwd)/_install/$ARCH]"
  [WORKSPACE] base directory which include the source files [default: $(pwd)]"
```
```
./mktoolchain.sh arm binutils
./mktoolchain.sh arm linux_uapi_headers
...
```

### mktoolchain.pl
```
Usage: mktoolchain.pl [options]
  --help|-h         display this page
  --verbose         verbose mode
  --arch <arg>      arm | aarch64 | x86_64 [default: arm]
  --libc <arg>      glibc | musl [default: glibc]
  --destdir <arg>   where to install the toolchain [default: ./_install/arm-glibc]
  --jobs|-j <arg>   pass to make
```
```
./mktoolchain.pl --arch aarch64 --libc musl -j8
```
