# Toolchain-make

[![Build Status](https://travis-ci.com/yonzkon/toolchain-make.svg?branch=master)](https://travis-ci.com/yonzkon/toolchain-make)

Make cross toolchains.

## Supported architectures

- arm
- aarch64
- x86_64

## Usage

```
Usage: make.pl [options]
  --help|-h         display this page
  --verbose         verbose mode
  --arch <arg>      arm | aarch64 | x86_64 [default: arm]
  --libc <arg>      glibc | musl [default: glibc]
  --destdir <arg>   where to install the toolchain [default: ./_install/arm-glibc]
  --jobs|-j <arg>   pass to make
```
```
./make.pl --arch aarch64 --libc musl -j8
```
