#!/bin/sh

usage()
{
	echo "Usage: rootfs.sh {COMMAND} [PREFIX]"
	echo ""
	echo "    {COMMAND} base | etc"
	echo "    [PREFIX]  where to install the toolchain [default: ./_install]"
}

# usage
[ -z "$1" ] || [ "$1" == "--help" ] && usage && exit

# environment
PWD=$(pwd)
SCRIPT_PATH=$0
SCRIPT_DIR=${SCRIPT_PATH%/*}
[ ! -z "$2" ] && PREFIX=$PWD/$2 || PREFIX=$PWD/_install
COMMAND=$(tr [A-Z] [a-z] <<<$1)

build_rootfs()
{
	mkdir -p $PREFIX
	cd $PREFIX

	# /
	mkdir -p etc bin sbin lib usr var
	mkdir -p dev proc sys tmp && chmod 1777 tmp
	mkdir -p root home
	mkdir -p opt mnt

	# /etc
	mkdir -p etc/init.d etc/udev/rules.d
	touch etc/inittab etc/fstab etc/profile etc/passwd etc/group etc/resolv.conf etc/inetd.conf
	touch etc/init.d/rcS etc/udev/rules.d/99-custom.rules
	chmod +x etc/init.d/rcS
	chmod 0600 etc/passwd etc/group

	# /usr
	mkdir -p usr/bin usr/sbin usr/lib usr/include usr/share usr/src usr/local

	# /var
	mkdir -p var/lib var/lock var/log var/mail var/run var/spool var/tmp && chmod 1777 var/tmp

	# /dev
	sudo mknod -m 600 dev/mem c 1 1
	sudo mknod -m 666 dev/null c 1 3
	sudo mknod -m 666 dev/zero c 1 5
	sudo mknod -m 644 dev/random c 1 8
	sudo mknod -m 600 dev/tty0 c 4 0
	sudo mknod -m 600 dev/tty1 c 4 1
	sudo mknod -m 600 dev/ttyS0 c 4 64
	sudo mknod -m 666 dev/tty c 5 0
	sudo mknod -m 600 dev/console c 5 1
	sudo mknod -m 666 dev/ptmx c 5 2
	mkdir dev/pts
	mkdir dev/shm
	ln -sf /proc/self/fd/ dev/fd
	ln -sf /proc/self/fd/0 dev/stdin
	ln -sf /proc/self/fd/1 dev/stdout
	ln -sf /proc/self/fd/2 dev/stderr
	for i in $(seq 0 3); do
		sudo mknod -m 600 dev/mtd$i c 90 $(expr $i + $i)
		sudo mknod -m 600 dev/mtdblock$i b 31 $i
	done

	cd -
}

copy_etc()
{
	sudo cp -pr $SCRIPT_DIR/rootfs_etc/* $PREFIX/etc/
}

if [ "$1" == 'base' ]; then
	build_rootfs
elif [ "$1" == 'etc' ]; then
	copy_etc
fi

sudo chown -R 0:0 $PREFIX
