#!/bin/bash
set -e -u
# Fixed for bootstrapping in Debian 13 2026 + included toolchain
ARCHIVE=qt-everywhere-opensource-src-4.6.2.tar.gz
ARCHIVEDIR=qt-everywhere-opensource-src-4.6.2
. $KOBO_SCRIPT_DIR/build-common.sh

patch -d $ARCHIVEDIR -p0 < $PATCHESDIR/qt-everywhere-opensource-src-4.6.2_kobo.patch

pushd $ARCHIVEDIR
    cp src/corelib/global/qconfig-dist.h src/corelib/global/qconfig-kobo.h
    find src/3rdparty/ -name "PtrAndFlags.h" -exec sed -i 's/set(ptr);/this->set(ptr);/g' {} +

    echo "QMAKE_CFLAGS += -marm" >> mkspecs/qws/linux-arm-g++/qmake.conf
    echo "QMAKE_CXXFLAGS += -marm -fpermissive" >> mkspecs/qws/linux-arm-g++/qmake.conf

    ./configure $CPPFLAGS $LIBS -prefix ${DEVICEROOT} -release -no-accessibility -system-libmng -no-nis -no-cups \
        -no-feature-PRINTER \
        -no-feature-FILEDIALOG \
        -no-xshape -no-xrandr -no-xkb -no-xinerama -no-xcursor -no-sm -system-libpng \
        -system-libjpeg -qt-gif -qt-zlib -embedded arm -xplatform qws/linux-arm-g++ \
        -no-qt3support -exceptions -opensource -no-pch -qt-freetype -qt-gfx-qvfb \
        -confirm-license -dbus -ldbus-1 -nomake examples -nomake docs -nomake translations \
        -nomake demos -scripttools -xmlpatterns -no-opengl -depths all -qt-gfx-transformed \
        -qt-gfx-linuxfb -no-mouse-pc -no-mouse-linuxtp -no-mouse-linuxinput -no-mouse-tslib \
        -no-mouse-qvfb -no-mouse-qnx -no-armfpa -no-neon -openssl -lrt \
        -I${DEVICEROOT}/include/dbus-1.0 -I${DEVICEROOT}/lib/dbus-1.0/include \
        -qconfig kobo $QT_EXTRA_ARGS

    $MAKE -j$MAKE_JOBS
    $MAKE install
popd
markbuilt
