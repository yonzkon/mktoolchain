#!/bin/sh

usage()
{
	echo "Usage: toolchian.sh {ARCH} {COMMAND} [PREFIX, [WORKSPACE]]"
	echo ""
	echo "  {ARCH}    arm | i686 | x86_64 | ..."
	echo "  {COMMAND} binutils"
	echo "            linux_uapi_headers"
	echo "            gcc_compilers"
	echo "            glibc_headers_and_startup_files"
	echo "            gcc_libgcc"
	echo "            glibc"
	echo "            gcc"
	echo "            rootfs_busybox"
	echo "            rootfs_glibc"
	echo "            rootfs_readline"
	echo "            rootfs_ncurses"
	echo "            rootfs_gdb"
	echo "            rootfs_binutils"
	echo "            rootfs_make"
	echo "            rootfs_bash"
	echo "            simplify_rootfs"
	echo "  [PREFIX]  where to install the toolchain [default: /opt/cross_\$ARCH]"
	echo "  [WORKSPACE] base directory which include the source files [default: $(pwd)]"
}

# usage
[ -z "$1" ] || [ "$1" == "--help" ] && usage && exit

# environment
PWD=$(pwd)
SCRIPT_PATH=$0
SCRIPT_DIR=${SCRIPT_PATH%/*}

CFLAGS='-O2 -pipe -fomit-frame-pointer' #-fno-stack-protector
CXXFLAGS='-O2 -pipe -fomit-frame-pointer'

ARCH=$1
COMMAND=$(echo "$2" |tr [A-Z] [a-z])

if [ -z "$3" ]; then
	PREFIX=/opt/cross-$ARCH
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

TARGET=$ARCH-unknown-linux-gnu
[ "$ARCH" == "arm" ] && TARGET+=eabi

[[ $PATH =~ "$PREFIX/bin" ]] || PATH=$PATH:$PREFIX/bin
#export LD_LIBRARY_PATH=$ROOTFS/lib
#export C_INCLUDE_PATH=$ROOTFS/include
#export CPLUS_INCLUDE_PATH=$C_INCLUDE_PATH
#export PKG_CONFIG_PATH=$ROOTFS/lib/pkgconfig:$PKG_CONFIG_PATH

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

ROOTFS=$WORKSPACE/rootfs
ROOTFS_CONFIG="--prefix=$ROOTFS/usr --build=$MACHTYPE --host=$TARGET"

source $SCRIPT_DIR/version-gcc-6.3.0

# common funcs
tarball_fetch_and_extract()
{
	local URI=$1
	local TARBALL=$(echo "$URI" |sed -e 's/^.*\///g')
	local FULL=$(echo "$TARBALL" |sed -e 's/\.tar.*$//g')
	local NAME=$(echo "$FULL" |sed -e 's/-.*$//g')

	if [ ! -e $TARBALL ]; then
		echo "fetching $TARBALL..."
		curl $URI -o $TARBALL
		if [ $? -ne 0 ]; then
			rm $TARBALL
			echo "failed to fetch $TARBALL...exit"
			exit
		fi
	fi

	if [ ! -e $FULL ]; then
		echo "extracting $TARBALL..."
		tar -xf $TARBALL
		ln -sf $FULL $NAME
	fi
}

build_rootfs()
{
	local URI=$1
	local TAR=${URI##*/}
	local NAME=${TAR%-*}
	local CONFIG=$2
	local MAKEOPTS=$3
	local BUILD=build-rootfs_$NAME

	tarball_fetch_and_extract $URI

	mkdir -p $BUILD && cd $BUILD
	../$NAME/configure $CONFIG
	make -j$JOBS $MAKEOPTS
	make $MAKEOPTS install
	cd -
}

# main
binutils()
{
	local NAME=binutils
	local BUILD=build-$NAME

	tarball_fetch_and_extract $URI_BINUTILS

	mkdir -p $BUILD && cd $BUILD
	../$NAME/configure --prefix=$PREFIX --target=$TARGET --disable-multilib
	make -j$JOBS
	make install
	cd -
}

linux_uapi_headers()
{
	tarball_fetch_and_extract $URI_LINUX

	cd linux
	local INNER_ARCH=$ARCH
	[ "$ARCH" = i686 ] && INNER_ARCH=x86
	make ARCH=$INNER_ARCH INSTALL_HDR_PATH=$PREFIX/$TARGET headers_install
	cd -
}

gcc_compilers()
{
	local NAME=gcc
	local BUILD=build-$NAME

	tarball_fetch_and_extract $URI_GCC

	# deps of gcc
	cd $NAME
	tarball_fetch_and_extract $URI_GMP
	tarball_fetch_and_extract $URI_MPFR
	tarball_fetch_and_extract $URI_MPC
	tarball_fetch_and_extract $URI_ISL
	tarball_fetch_and_extract $URI_CLOOG
	cd -

	# build gcc
	mkdir -p $BUILD && cd $BUILD
	../$NAME/configure --prefix=$PREFIX --target=$TARGET --enable-languages=c,c++ --disable-multilib
	make -j$JOBS all-gcc
	make install-gcc
	cd -
}

glibc_headers_and_startup_files()
{
	local NAME=glibc
	local BUILD=build-$NAME

	tarball_fetch_and_extract $URI_GLIBC

	mkdir -p $BUILD && cd $BUILD
	../$NAME/configure --prefix=$PREFIX/$TARGET --build=$MACHTYPE --host=$TARGET \
		--disable-multilib --with-headers=$PREFIX/$TARGET/include --without-selinux \
		libc_cv_forced_unwind=yes \
		libc_cv_ssp=no libc_cv_ssp_strong=no # libc_cv_ssp is to resolv __stack_chk_gurad for x86_64
	make install-bootstrap-headers=yes install-headers
	make -j$JOBS csu/subdir_lib
	install csu/crt1.o csu/crti.o csu/crtn.o $PREFIX/$TARGET/lib
	$TARGET-gcc -nostdlib -nostartfiles -shared -x c /dev/null -o $PREFIX/$TARGET/lib/libc.so
	touch $PREFIX/$TARGET/include/gnu/stubs.h
	cd -
}

gcc_libgcc()
{
	cd build-gcc
	make -j$JOBS all-target-libgcc
	make install-target-libgcc
	cd -
}

glibc()
{
	cd build-glibc
	make -j$JOBS
	make install
	cd -
}

gcc()
{
	cd build-gcc
	make -j$JOBS
	make install
	cd -
}

rootfs_busybox()
{
	tarball_fetch_and_extract $URI_BUSYBOX

	cd busybox
	make gconfig && make -j$JOBS && make install
	mkdir -p $ROOTFS && cp -a _install/* $ROOTFS
	cd -
}

rootfs_glibc()
{
	local NAME=glibc
	local BUILD=build-$FUNCNAME

	mkdir -p $BUILD && cd $BUILD
	../$NAME/configure --prefix=/usr --build=$MACHTYPE --host=$TARGET \
		--disable-multilib --with-headers=$PREFIX/$TARGET/include \
		libc_cv_forced_unwind=yes \
		libc_cv_ssp=no libc_cv_ssp_strong=no # libc_cv_ssp is to resolv __stack_chk_gurad for x86_64
	make -j$JOBS
	make install install_root=$ROOTFS
	sed -i 's#/lib/##g' $ROOTFS/lib/libc.so $ROOTFS/lib/libm.so $ROOTFS/lib/libpthread.so
	cd -
}

simplify_rootfs()
{
	find $ROOTFS -type f -perm -0111 -exec $TARGET-strip {} \;
	find $ROOTFS -type f -name '*.a' -exec rm {} \;
}

echo "start build and install to $PREFIX"
cd $WORKSPACE

case "$COMMAND" in
	binutils) binutils;;
	linux_uapi_headers) linux_uapi_headers;;
	gcc_compilers) gcc_compilers;;
	glibc_headers_and_startup_files) glibc_headers_and_startup_files;;
	gcc_libgcc) gcc_libgcc;;
	glibc) glibc;;
	gcc) gcc;;
	rootfs_busybox) rootfs_busybox ;;
	rootfs_glibc) rootfs_glibc ;;
	rootfs_readline) build_rootfs $URI_READLINE \
		"$ROOTFS_CONFIG --prefix=/usr --libdir=/lib --enable-shared --disable-static" \
		"DESTDIR=$ROOTFS" ;; #bash_cv_wcwidth_broken=yes
	rootfs_ncurses) build_rootfs $URI_NCURSES \
		"$ROOTFS_CONFIG --libdir=$ROOTFS/lib --with-shared --without-gpm --with-termlib" \
		"-C ncurses" ;;
	rootfs_gdb) build_rootfs $URI_GDB "$ROOTFS_CONFIG" ;;
	rootfs_binutils) build_rootfs $URI_BINUTILS "$ROOTFS_CONFIG --disable-multilib" ;;
	rootfs_make) build_rootfs $URI_MAKE "$ROOTFS_CONFIG --without-guile" ;;
	rootfs_bash) build_rootfs $URI_BASH "$ROOTFS_CONFIG" ;;
	simplify_rootfs) simplify_rootfs ;;
	*) usage && exit ;;
esac

echo "finished $COMMAND"
cd $PWD
