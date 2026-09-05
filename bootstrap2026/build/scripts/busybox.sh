#!/bin/bash
set -e -u
# Fixed for bootstrapping in Debian 13 2026 + included toolchain
ARCHIVE=busybox-1.17.1.tar.bz2
ARCHIVEDIR=busybox-1.17.1
. $KOBO_SCRIPT_DIR/build-common.sh

if [ -d "$PATCHESDIR" ]; then
    [ -f "$PATCHESDIR/busybox-1.17.1.patch" ] && patch -p0 < "$PATCHESDIR/busybox-1.17.1.patch"
    [ -f "$PATCHESDIR/busybox-1.17.1-make.patch" ] && patch -p0 < "$PATCHESDIR/busybox-1.17.1-make.patch"
    [ -f "$PATCHESDIR/busybox-1.17.1-sysinfo.patch" ] && patch -p0 < "$PATCHESDIR/busybox-1.17.1-sysinfo.patch"
fi

pushd $ARCHIVEDIR
    if ! grep -q "sys/sysinfo.h" include/libbb.h; then
        sed -i '1i#include <sys/sysinfo.h>\n#define _LINUX_SYSINFO_H' include/libbb.h
        sed -i '/struct sysinfo {/,/int sysinfo(struct sysinfo/d' include/libbb.h
    fi

    $MAKE defconfig
    $MAKE -j$MAKE_JOBS CROSS_COMPILE="${CROSSTARGET}-" CFLAGS_EXTRA="-fno-strict-aliasing" install
    cp -a _install/* /${DEVICEROOT}
popd
markbuilt
