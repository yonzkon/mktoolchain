#!/bin/sh

##
# usage
#

usage()
{
    echo "Usage: mktoolchian.sh {ARCH} {COMMAND} [PREFIX, [WORKSPACE]]"
    echo "  {ARCH}    arm | aarch64 | i686 | x86_64 | ..."
    echo "  {COMMAND} binutils"
    echo "            linux_uapi_headers"
    echo "            gcc_compilers"
    echo "            glibc_headers_and_startup_files"
    echo "            gcc_libgcc"
    echo "            glibc"
    echo "            gcc"
    echo ""
    echo "            rootfs_base"
    echo "            rootfs_busybox"
    echo "            rootfs_glibc"
    echo "            rootfs_readline"
    echo "            rootfs_ncurses"
    echo "            rootfs_gdb"
    echo "            rootfs_binutils"
    echo "            rootfs_bash"
    echo "            strip_rootfs"
    echo ""
    echo "            all_compilers"
    echo "            all_rootfs"
    echo "            all"
    echo "  [PREFIX]  where to install the toolchain [default: $(pwd)/_install/$ARCH]"
    echo "  [WORKSPACE] base directory which include the source files [default: $(pwd)]"
}

[ -z "$1" ] || [ "$1" == "--help" ] && usage && exit

##
# parse cmdline & setup dir environment
#

PWD=$(pwd)
SCRIPT_PATH=$0
SCRIPT_DIR=$(dirname $(readlink -f $0))

ARCH=$1
COMMAND=$(echo "$2" |tr [A-Z] [a-z])

if [ -z "$3" ]; then
    PREFIX=$(pwd)/_install/$ARCH
elif [ -z $(echo "$3" |grep -e '^/') ]; then
    PREFIX=$(pwd)/$3
else
    PREFIX=$3
fi

if [ -z "$4" ]; then
    WORKSPACE=$(pwd)
elif [ -z $(echo "$4" |grep -e '^/') ]; then
    WORKSPACE=$(pwd)/$4
else
    WORKSPACE=$4
fi

DIST_DIR=$WORKSPACE/dist
SRC_DIR=$WORKSPACE/src
BUILD_DIR=$WORKSPACE/build
mkdir -p $DIST_DIR $SRC_DIR $BUILD_DIR

##
# target & compiler
#

source $SCRIPT_DIR/version-gcc-4.9.4

CFLAGS='-O2 -pipe -fomit-frame-pointer' #-fno-stack-protector
CXXFLAGS='-O2 -pipe -fomit-frame-pointer'

TARGET=$ARCH-none-linux-gnu
[ "$ARCH" == "arm" ] && TARGET+=eabi

[[ $PATH =~ "$PREFIX/bin" ]] || PATH=$PATH:$PREFIX/bin

case $(uname -s) in
Linux)
    JOBS=$(grep -c ^processor /proc/cpuinfo)
    ;;
FreeBSD)
    JOBS=$(sysctl -n hw.ncpu)
    ;;
Darwin)
    JOBS=$(sysctl -n machdep.cpu.core_count)
    ulimit -n 1024
    ;;
*)
    JOBS=1
    ;;
esac

##
# for rootfs only
#

if [[ $COMMAND =~ "rootfs" ]] || [[ $COMMAND = "all" ]]; then
    ROOTFS=$PREFIX-rootfs
    ROOTFS_CONFIG="--prefix=$ROOTFS/usr --build=$MACHTYPE --host=$TARGET"
    # env below is not necesarry as set --host=$TARGET
    #CC=$TARGET-gcc
    #CXX=$TARGET-g++
    #CPP=$TARGET-cpp
    #AS=$TARGET-as
    #LD=$TARGET-ld
    #STRIP=$TARGET-strip
    LD_LIBRARY_PATH=$ROOTFS/lib
    C_INCLUDE_PATH=$ROOTFS/include
    CPLUS_INCLUDE_PATH=$C_INCLUDE_PATH
    PKG_CONFIG_PATH=$ROOTFS/lib/pkgconfig:$PKG_CONFIG_PATH
    RPATH='-Wl,-rpath,$$\ORIGIN:$$\ORIGIN/../lib'
    mkdir -p $ROOTFS
fi

##
# common functions
#

# echo -e "\e[30m 黑色 \e[0m"
# echo -e "\e[31m 红色 \e[0m"
# echo -e "\e[32m 绿色 \e[0m"
# echo -e "\e[33m 黄色 \e[0m"
# echo -e "\e[34m 蓝色 \e[0m"
# echo -e "\e[35m 紫色 \e[0m"
# echo -e "\e[36m 青色 \e[0m"
# echo -e "\e[37m 白色 \e[0m"

do_build()
{
    echo -e "\033[32m($(date '+%Y-%m-%d %H:%M:%S')): Building $1\033[0m"
    $*
    echo -e "\033[32m($(date '+%Y-%m-%d %H:%M:%S')): Finished $1\033[0m"
}

err_exit()
{
    echo -e "\033[31m($(date '+%Y-%m-%d %H:%M:%S')): $1\033[0m"
    exit
}

tarball_fetch_and_extract()
{
    local URI=$1
    local TARBALL=$(echo "$URI" |sed -e 's/^.*\///g')
    local NAME=$(echo "$TARBALL" |sed -e 's/\.tar.*$//g')

    if [ ! -e $DIST_DIR/$TARBALL ]; then
        echo "fetching $TARBALL..."
        curl $URI -o $DIST_DIR/$TARBALL
        if [ $? -ne 0 ]; then
            rm $DIST_DIR/$TARBALL
            echo "failed to fetch $TARBALL...exit"
            exit
        fi
    fi

    if [ ! -e $SRC_DIR/$NAME ]; then
        echo "extracting $TARBALL..."
        tar -xf $DIST_DIR/$TARBALL -C $SRC_DIR
    fi
}

##
# toolchain functions
#

binutils()
{
    tarball_fetch_and_extract $URI_BINUTILS

    local NAME=$(echo "$URI_BINUTILS" |sed -e 's/^.*\///g' |sed -e 's/\.tar.*$//g')
    mkdir -p $BUILD_DIR/$TARGET/$NAME && cd $BUILD_DIR/$TARGET/$NAME
    $SRC_DIR/$NAME/configure --prefix=$PREFIX --target=$TARGET --disable-multilib
    make -j$JOBS || err_exit "build binutils failed"
    make install
    cd -
}

linux_uapi_headers()
{
    tarball_fetch_and_extract $URI_LINUX

    local NAME=$(echo "$URI_LINUX" |sed -e 's/^.*\///g' |sed -e 's/\.tar.*$//g')
    cd $SRC_DIR/$NAME
    local INNER_ARCH=$ARCH
    [ "$ARCH" = i686 ] && INNER_ARCH=x86
    make ARCH=$INNER_ARCH INSTALL_HDR_PATH=$PREFIX/$TARGET headers_install
    cd -
}

gcc_compilers()
{
    tarball_fetch_and_extract $URI_GCC
    if [[ $URI_GCC =~ "gcc-4.9.4" ]]; then
        sed -ie 's/spill_indirect_levels++;/spill_indirect_levels = spill_indirect_levels + 1;/g' \
            $SRC_DIR/gcc-4.9.4/gcc/reload1.c
    fi
    tarball_fetch_and_extract $URI_GMP
    tarball_fetch_and_extract $URI_MPFR
    tarball_fetch_and_extract $URI_MPC
    #tarball_fetch_and_extract $URI_ISL
    #tarball_fetch_and_extract $URI_CLOOG

    local NAME=$(echo "$URI_GCC" |sed -e 's/^.*\///g' |sed -e 's/\.tar.*$//g')

    # deps of gcc
    cd $SRC_DIR/$NAME
    local NAME_GMP=$(echo "$URI_GMP" |sed -e 's/^.*\///g' |sed -e 's/\.tar.*$//g')
    local NAME_GMP_SHORT=$(echo "$NAME_GMP" |sed -e 's/-.*$//g')
    ln -sf ../$NAME_GMP $NAME_GMP_SHORT

    local NAME_MPFR=$(echo "$URI_MPFR" |sed -e 's/^.*\///g' |sed -e 's/\.tar.*$//g')
    local NAME_MPFR_SHORT=$(echo "$NAME_MPFR" |sed -e 's/-.*$//g')
    ln -sf ../$NAME_MPFR $NAME_MPFR_SHORT

    local NAME_MPC=$(echo "$URI_MPC" |sed -e 's/^.*\///g' |sed -e 's/\.tar.*$//g')
    local NAME_MPC_SHORT=$(echo "$NAME_MPC" |sed -e 's/-.*$//g')
    ln -sf ../$NAME_MPC $NAME_MPC_SHORT
    cd -

    # build gcc
    mkdir -p $BUILD_DIR/$TARGET/$NAME && cd $BUILD_DIR/$TARGET/$NAME
    $SRC_DIR/$NAME/configure --prefix=$PREFIX --target=$TARGET \
        --enable-languages=c,c++ --disable-multilib
    make -j$JOBS all-gcc || err_exit "build gcc_compilers failed"
    make install-gcc
    cd -
}

glibc_headers_and_startup_files()
{
    tarball_fetch_and_extract $URI_GLIBC

    local NAME=$(echo "$URI_GLIBC" |sed -e 's/^.*\///g' |sed -e 's/\.tar.*$//g')
    mkdir -p $BUILD_DIR/$TARGET/$NAME && cd $BUILD_DIR/$TARGET/$NAME
    $SRC_DIR/$NAME/configure \
        --prefix=$PREFIX/$TARGET --build=$MACHTYPE --host=$TARGET \
        --with-headers=$PREFIX/$TARGET/include \
        --disable-multilib \
        --without-selinux \
        --enable-obsolete-rpc \
        libc_cv_forced_unwind=yes \
        libc_cv_ssp=no \
        libc_cv_ssp_strong=no # libc_cv_ssp is to resolv __stack_chk_gurad for x86_64
    make install-bootstrap-headers=yes install-headers
    make -j$JOBS csu/subdir_lib || err_exit "build glibc headers failed"
    install csu/crt1.o csu/crti.o csu/crtn.o $PREFIX/$TARGET/lib
    $TARGET-gcc -nostdlib -nostartfiles -shared -x c /dev/null -o $PREFIX/$TARGET/lib/libc.so
    touch $PREFIX/$TARGET/include/gnu/stubs.h
    cd -
}

gcc_libgcc()
{
    local NAME=$(echo "$URI_GCC" |sed -e 's/^.*\///g' |sed -e 's/\.tar.*$//g')
    cd $BUILD_DIR/$TARGET/$NAME
    make -j$JOBS all-target-libgcc || err_exit "build gcc_libgcc failed"
    make install-target-libgcc
    cd -
}

glibc()
{
    local NAME=$(echo "$URI_GLIBC" |sed -e 's/^.*\///g' |sed -e 's/\.tar.*$//g')
    cd $BUILD_DIR/$TARGET/$NAME
    make -j$JOBS || err_exit "build glibc failed"
    make install
    cd -
}

gcc()
{
    local NAME=$(echo "$URI_GCC" |sed -e 's/^.*\///g' |sed -e 's/\.tar.*$//g')
    cd $BUILD_DIR/$TARGET/$NAME
    make -j$JOBS || err_exit "build gcc failed"
    make install
    cd -
}

##
# rootfs functions
#

build_rootfs()
{
    local URI=$1
    local TAR=${URI##*/}
    local NAME=${TAR%-*}
    local CONFIG=$2
    local MAKEOPTS=$3

    tarball_fetch_and_extract $URI

    local NAME=$(echo "$URI" |sed -e 's/^.*\///g' |sed -e 's/\.tar.*$//g')
    mkdir -p $BUILD_DIR/$TARGET/$NAME-rootfs && cd $BUILD_DIR/$TARGET/$NAME-rootfs
    $SRC_DIR/$NAME/configure $CONFIG
    make -j$JOBS $MAKEOPTS || err_exit "build rootfs_$NAME failed"
    make $MAKEOPTS install
    cd -
}

rootfs_base()
{
    mkdir -p $ROOTFS && cd $ROOTFS
    mkdir -p etc dev proc sys tmp var opt mnt srv
    mkdir -p dev/pts
    mkdir -p dev/shm
    mkdir -p var/empty
    mkdir -p var/log
    mkdir -p var/lock
    mkdir -p var/run
    mkdir -p var/tmp
    mkdir -p root home
    chmod 1777 tmp var/tmp
    cp -a $SCRIPT_DIR/rootfs-etc/* ./etc/
    cd -
}

rootfs_busybox()
{
    tarball_fetch_and_extract $URI_BUSYBOX

    local NAME=$(echo "$URI_BUSYBOX" |sed -e 's/^.*\///g' |sed -e 's/\.tar.*$//g')
    mkdir -p $BUILD_DIR/$TARGET/$NAME-rootfs && cd $BUILD_DIR/$TARGET/$NAME-rootfs
    cp -a $SRC_DIR/$NAME/* .
    make defconfig
    sed -ie 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/g' \
        $BUILD_DIR/$TARGET/$NAME-rootfs/.config
    make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabi- install -j$JOBS ||
        err_exit "build rootfs_busybox failed"
    # busybox use "./_install" as default install dir like us
    mkdir -p $ROOTFS && cp -a _install/* $ROOTFS
    cd -
}

rootfs_glibc()
{
    local NAME=$(echo "$URI_GLIBC" |sed -e 's/^.*\///g' |sed -e 's/\.tar.*$//g')
    mkdir -p $BUILD_DIR/$TARGET/$NAME-rootfs && cd $BUILD_DIR/$TARGET/$NAME-rootfs
    $SRC_DIR/$NAME/configure \
        --prefix=/usr --build=$MACHTYPE --host=$TARGET \
        --with-headers=$PREFIX/$TARGET/include \
        --disable-multilib \
        --without-selinux \
        --enable-obsolete-rpc \
        libc_cv_forced_unwind=yes \
        libc_cv_ssp=no \
        libc_cv_ssp_strong=no # libc_cv_ssp is to resolv __stack_chk_gurad for x86_64
    make -j$JOBS || err_exit "build rootfs_glibc failed"
    make install install_root=$ROOTFS
    sed -i 's#/lib/##g' $ROOTFS/lib/libc.so $ROOTFS/lib/libm.so $ROOTFS/lib/libpthread.so
    cd -
}

rootfs_readline()
{
    export bash_cv_wcwidth_broken=yes && build_rootfs $URI_READLINE \
        "$ROOTFS_CONFIG --prefix=/usr --libdir=/lib --enable-shared --disable-static" \
        "DESTDIR=$ROOTFS" #bash_cv_wcwidth_broken=yes
}

rootfs_ncurses()
{
    tarball_fetch_and_extract $URI_NCURSES

    local NAME=$(echo "$URI_NCURSES" |sed -e 's/^.*\///g' |sed -e 's/\.tar.*$//g')
    mkdir -p $BUILD_DIR/$TARGET/$NAME-rootfs && cd $BUILD_DIR/$TARGET/$NAME-rootfs
    $SRC_DIR/$NAME/configure $ROOTFS_CONFIG \
        --libdir=$ROOTFS/lib --with-shared --without-gpm --with-termlib
    # first make always failed ...
    make -j$JOBS -C ncurses || make -j$JOBS -C ncurses ||
        err_exit "build rootfs_$NAME failed"
    make $MAKEOPTS install
    cd -
}

rootfs_gdb()
{
    build_rootfs $URI_GDB "$ROOTFS_CONFIG"
}

rootfs_binutils()
{
    build_rootfs $URI_BINUTILS "$ROOTFS_CONFIG --disable-multilib"
}

rootfs_bash()
{
    build_rootfs $URI_BASH "$ROOTFS_CONFIG"
}

strip_rootfs()
{
    cp -a $ROOTFS $ROOTFS-stripped
    find $ROOTFS-stripped -type f -perm -0111 -exec $TARGET-strip {} \;
    find $ROOTFS-stripped -type f -name '*.a' -exec rm {} \;
}

##
# convenient functions
#

all_compilers()
{
    do_build binutils
    do_build linux_uapi_headers
    do_build gcc_compilers
    do_build glibc_headers_and_startup_files
    do_build gcc_libgcc
    do_build glibc
    do_build gcc
}

all_rootfs()
{
    do_build rootfs_base
    do_build rootfs_busybox
    do_build rootfs_glibc
    do_build rootfs_readline
    do_build rootfs_ncurses
    do_build rootfs_gdb
    do_build rootfs_binutils
    do_build rootfs_bash
    do_build strip_rootfs
}

all()
{
    do_build all_compilers
    do_build all_rootfs
}

##
# main: command parser
#

echo "start build and install to $PREFIX"
cd $WORKSPACE

case "$COMMAND" in
    binutils) do_build binutils;;
    linux_uapi_headers) do_build linux_uapi_headers;;
    gcc_compilers) do_build gcc_compilers;;
    glibc_headers_and_startup_files) do_build glibc_headers_and_startup_files;;
    gcc_libgcc) do_build gcc_libgcc;;
    glibc) do_build glibc;;
    gcc) do_build gcc;;

    rootfs_base) do_build rootfs_base ;;
    rootfs_busybox) do_build rootfs_busybox ;;
    rootfs_glibc) do_build rootfs_glibc ;;
    rootfs_readline) do_build rootfs_readline ;;
    rootfs_ncurses) do_build rootfs_ncurses ;;
    rootfs_gdb) do_build rootfs_gdb ;;
    rootfs_binutils) do_build rootfs_binutils ;;
    rootfs_bash) do_build rootfs_bash ;;
    strip_rootfs) do_build strip_rootfs ;;

    all_compilers) do_build all_compilers ;;
    all_rootfs) do_build all_rootfs ;;
    all) do_build all ;;
    *) usage && exit ;;
esac

echo "finished $COMMAND"
cd $PWD
