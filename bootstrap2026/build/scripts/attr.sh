#!/bin/bash
set -e -u
# Fixed for bootstrapping in Debian 13 2026 + included toolchain
ARCHIVE=attr_2.4.43-1.tar.gz
ARCHIVEDIR=attr-2.4.43
. $KOBO_SCRIPT_DIR/build-common.sh

pushd $ARCHIVEDIR
    LIBTOOL="${LIBTOOL:-arm-linux-libtool} --tag=CC" CC="${CC}" ./configure --host=${CROSSTARGET} --prefix=/${DEVICEROOT}

    $MAKE install LIBTOOL="${LIBTOOL:-arm-linux-libtool} --tag=CC"
    $MAKE install-dev LIBTOOL="${LIBTOOL:-arm-linux-libtool} --tag=CC"
    $MAKE install-lib LIBTOOL="${LIBTOOL:-arm-linux-libtool} --tag=CC"
popd
markbuilt
