#!/bin/bash
set -e -u
# Fixed for bootstrapping in Debian 13 2026 + included toolchain
ARCHIVE=libmng-1.0.10.tar.gz
ARCHIVEDIR=libmng-1.0.10
. $KOBO_SCRIPT_DIR/build-common.sh

pushd $ARCHIVEDIR
	cp unmaintained/autogen.sh .
	if [ -f unmaintained/configure.in ]; then
		cp unmaintained/configure.in .
	elif [ -f makefiles/configure.in ]; then
		cp makefiles/configure.in .
	fi

	patch -p0 < $PATCHESDIR/libmng-autogen.patch

	if [ -f configure.in ]; then
		sed -i '/AM_C_PROTOTYPES/d' configure.in
		sed -i 's/AM_PROG_LIBTOOL/LT_INIT/' configure.in
	fi

	./autogen.sh
	CPPFLAGS="${CPPFLAGS}" LDFLAGS="${LDFLAGS}" ./configure --prefix=/ --host=${CROSSTARGET}
	$MAKE -j$MAKE_JOBS
	$MAKE DESTDIR=/${DEVICEROOT} install
popd
markbuilt
