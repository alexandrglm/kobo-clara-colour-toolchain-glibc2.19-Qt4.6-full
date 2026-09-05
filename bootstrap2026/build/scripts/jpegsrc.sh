#!/bin/bash
set -e -u
# Fixed for bootstrapping in Debian 13 2026 + included toolchain
ARCHIVE=jpegsrc.v6b.tar.gz
ARCHIVEDIR=jpeg-6b
. $KOBO_SCRIPT_DIR/build-common.sh

patch -p0 < $PATCHESDIR/jpeg6b-config-sub.patch
pushd $ARCHIVEDIR
	CC="arm-linux-gcc" AR="arm-linux-ar r" RANLIB="arm-linux-ranlib" ./configure \
		--host=${CROSSTARGET} \
		--enable-shared \
		--enable-static \
		--prefix=/${DEVICEROOT} || true

	if [ ! -f ./libtool ]; then
		./ltconfig ./ltmain.sh ${CROSSTARGET}
	fi

	$MAKE -j$MAKE_JOBS
	$MAKE install
popd
markbuilt
