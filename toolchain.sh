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
	echo "            rootfs_binutils"
	echo "            rootfs_glibc"
	echo "            rootfs_make"
	echo "            rootfs_readline"
	echo "            rootfs_bash"
	echo "            rootfs_ncurses"
	echo "            rootfs_gdb"
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

ROOTFS=$WORKSPACE/rootfs

TARGET=$ARCH-unknown-linux-gnu
[ "$ARCH" == "arm" ] && TARGET+=eabi

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

# PATH & export PATH
# bash & '.' / source
[[ $PATH =~ "$PREFIX/bin" ]] || PATH=$PATH:$PREFIX/bin
#export PATH=$PREFIX/bin:$PATH
#export LD_LIBRARY_PATH=$ROOTFS/lib
#export C_INCLUDE_PATH=$ROOTFS/include
#export CPLUS_INCLUDE_PATH=$C_INCLUDE_PATH
#export PKG_CONFIG_PATH=$ROOTFS/lib/pkgconfig:$PKG_CONFIG_PATH

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

# main
binutils()
{
	local NAME=binutils
	local URI=http://mirrors.ustc.edu.cn/gnu/$NAME/$NAME-2.27.tar.bz2
	local BUILD=build-$NAME

	tarball_fetch_and_extract $URI

	mkdir -p $BUILD && cd $BUILD
	../$NAME/configure --prefix=$PREFIX --target=$TARGET --disable-multilib
	make -j$JOBS
	make install
	cd -
}

linux_uapi_headers()
{
	local NAME=linux
	local URI=http://mirrors.ustc.edu.cn/kernel.org/linux/kernel/v4.x/$NAME-4.4.48.tar.xz

	tarball_fetch_and_extract $URI

	cd $NAME
	local INNER_ARCH=$ARCH
	[ "$ARCH" = i686 ] && INNER_ARCH=x86
	make ARCH=$INNER_ARCH INSTALL_HDR_PATH=$PREFIX/$TARGET headers_install
	cd -
}

gmp()
{
	local NAME=gmp
	local URI=http://mirrors.ustc.edu.cn/gnu/$NAME/$NAME-6.1.1.tar.xz

	tarball_fetch_and_extract $URI
}

mpfr()
{
	local NAME=mpfr
	local URI=http://mirrors.ustc.edu.cn/gnu/$NAME/$NAME-3.1.4.tar.xz

	tarball_fetch_and_extract $URI
}

mpc()
{
	local NAME=mpc
	local URI=http://mirrors.ustc.edu.cn/gnu/$NAME/$NAME-1.0.3.tar.gz

	tarball_fetch_and_extract $URI
}

isl()
{
	local NAME=isl
	local URI=http://isl.gforge.inria.fr/$NAME-0.14.tar.xz

	tarball_fetch_and_extract $URI
}

cloog()
{
	local NAME=cloog
	local URI=http://www.bastoul.net/cloog/pages/download/$NAME-0.18.4.tar.gz

	tarball_fetch_and_extract $URI
}

gcc_compilers()
{
	local NAME=gcc
	local URI=http://mirrors.ustc.edu.cn/gnu/$NAME/$NAME-4.9.4/$NAME-4.9.4.tar.bz2
	local BUILD=build-$NAME

	tarball_fetch_and_extract $URI

	# deps of gcc
	cd $NAME
	gmp
	mpfr
	mpc
	isl
	cloog
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
	local URI=http://mirrors.ustc.edu.cn/gnu/$NAME/$NAME-2.23.tar.xz
	local BUILD=build-$NAME

	tarball_fetch_and_extract $URI

	mkdir -p $BUILD && cd $BUILD
	../$NAME/configure --prefix=$PREFIX/$TARGET --build=$MACHTYPE --host=$TARGET \
		--disable-multilib --with-headers=$PREFIX/$TARGET/include \
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
	local NAME=busybox
	local URI=https://www.busybox.net/downloads/$NAME-1.24.2.tar.bz2
	local BUILD=build-$FUNCNAME

	tarball_fetch_and_extract $URI

	cd $NAME
	make gconfig && make -j$JOBS && make install
	mkdir -p $ROOTFS && cp -a _install/* $ROOTFS
	cd -
}

rootfs_binutils()
{
	local NAME=binutils
	local BUILD=build-$FUNCNAME

	mkdir -p $BUILD && cd $BUILD
	../$NAME/configure --prefix=$ROOTFS/usr --build=$MACHTYPE --host=$TARGET --disable-multilib
	make -j$JOBS
	make install
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
	cd -
}

rootfs_make()
{
	local NAME=make
	local URI=http://mirrors.ustc.edu.cn/gnu/$NAME/$NAME-4.2.1.tar.gz
	local BUILD=build-$FUNCNAME

	tarball_fetch_and_extract $URI

	mkdir -p $BUILD && cd $BUILD
	../$NAME/configure --prefix=$ROOTFS/usr --build=$MACHTYPE --host=$TARGET \
		--without-guile
	make -j$JOBS
	make install
	cd -
}

rootfs_readline()
{
	#echo "[Unsolved Problem] missing simbol UP error ..."
	#exit

	local NAME=readline
	local URI=http://mirrors.ustc.edu.cn/gnu/$NAME/$NAME-6.3.tar.gz
	local BUILD=build-$FUNCNAME

	tarball_fetch_and_extract $URI

	mkdir -p $BUILD && cd $BUILD
	../$NAME/configure --prefix=/usr --build=$MACHTYPE --host=$TARGET \
		--enable-shared --disable-static \
		bash_cv_wcwidth_broken=yes
	make -j$JOBS
	make install DESTDIR=$ROOTFS
	cd -
}

rootfs_bash()
{
	local NAME=bash
	local URI=http://mirrors.ustc.edu.cn/gnu/$NAME/$NAME-4.3.30.tar.gz
	local BUILD=build-$FUNCNAME

	tarball_fetch_and_extract $URI

	mkdir -p $BUILD && cd $BUILD
	../$NAME/configure --prefix=$ROOTFS/usr --build=$MACHTYPE --host=$TARGET
	make -j$JOBS
	make install
	cd -
}

rootfs_ncurses()
{
	local NAME=ncurses
	local URI=http://mirrors.ustc.edu.cn/gnu/$NAME/$NAME-5.9.tar.gz
	local BUILD=build-$FUNCNAME

	tarball_fetch_and_extract $URI

	mkdir -p $BUILD && cd $BUILD
	../$NAME/configure --prefix=$ROOTFS/usr --build=$MACHTYPE --host=$TARGET \
		--with-shared --without-gpm #--with-termlib
	make -j$JOBS
	make install #DESTDIR=$ROOTFS
	cd -
}

rootfs_gdb()
{
	local NAME=gdb
	local URI=http://mirrors.ustc.edu.cn/gnu/$NAME/$NAME-7.10.1.tar.xz
	local BUILD=build-$FUNCNAME

	tarball_fetch_and_extract $URI

	mkdir -p $BUILD && cd $BUILD
	../$NAME/configure --prefix=$ROOTFS/usr --build=$MACHTYPE --host=$TARGET
	make -j$JOBS
	make install
	cd -
}

simplify_rootfs()
{
	local from=$ROOTFS
	local to=$ROOTFS/simplify

	# lib
	mkdir -p $to/lib
	for item in libc libm libcrypt libdl libpthread libutil libresolv libnss_dns libthread_db; do
		cp -dp $from/lib/$item.* $to/lib
		cp -dp $from/lib/$item-* $to/lib
	done
	for item in ld- libreadline libncurses; do
		cp -dp $from/lib/$item* $to/lib
	done
	cp -prd $from/lib/gconv $to/lib
	rm $to/lib/*.a

	# bin & sbin
	cp -prd $from/bin $from/sbin $to

	# strip
	$TARGET-strip $to/lib/* $to/bin/* $to/sbin/* &>/dev/null
}

echo "start build and install to $PREFIX"

cd $WORKSPACE

if [ "$COMMAND" == "binutils" ]; then
	binutils # 1
elif [ "$COMMAND" == "linux_uapi_headers" ]; then
	linux_uapi_headers # 2
elif [ "$COMMAND" == "gcc_compilers" ]; then
	gcc_compilers # 3
elif [ "$COMMAND" == "glibc_headers_and_startup_files" ]; then
	glibc_headers_and_startup_files # 4
elif [ "$COMMAND" == "gcc_libgcc" ]; then
	gcc_libgcc # 5
elif [ "$COMMAND" == "glibc" ]; then
	glibc # 6
elif [ "$COMMAND" == "gcc" ]; then
	gcc # 7
elif [ "$COMMAND" == "rootfs_busybox" ]; then
	rootfs_busybox # r0
elif [ "$COMMAND" == "rootfs_binutils" ]; then
	rootfs_binutils # r1
elif [ "$COMMAND" == "rootfs_glibc" ]; then
	rootfs_glibc # r2
elif [ "$COMMAND" == "rootfs_make" ]; then
	rootfs_make # r2
elif [ "$COMMAND" == "rootfs_readline" ]; then
	rootfs_readline # r3
elif [ "$COMMAND" == "rootfs_bash" ]; then
	rootfs_bash # r3
elif [ "$COMMAND" == "rootfs_ncurses" ]; then
	rootfs_ncurses # r4
elif [ "$COMMAND" == "rootfs_gdb" ]; then
	rootfs_gdb # r5
elif [ "$COMMAND" == "simplify_rootfs" ]; then
	simplify_rootfs # r6
else
	usage && exit
fi

cd $PWD
