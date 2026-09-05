# 1. Compilation Fixes

---

For a directory layout like this:

```bash
~/kobo/KoboLabs$ tree -L 2
.
├── fs
│   ├── bin
│   ├── etc
│   ├── include
│   ├── lib
│   ├── libexec
│   ├── man
│   ├── share
│   ├── usr
│   └── var
├── Kobo-Reader
│   ├── build
│   ├── documentation
│   ├── examples
│   ├── fickel
│   ├── FORK-FIXES-NOTES.md
│   ├── hw
│   ├── packages
│   ├── packages-v5
│   ├── patches
│   ├── poser
│   ├── README
│   └── toolchain
└── tmp

```

Where:

* `Kobo-Reader` is the repository path.
* `tmp` contains all temporary build files.
* `fs` is the chroot, or final environment, containing all compiled files.

A script a script that prompts for all the necessary details and lets initialise directly is available, [here](./setup-all.sh)

---

## Fixes to be applied before build-all

### 00.  Hardcoded Toolchain Fix

> [!IMPORTANT]
> KoboLabs build scripts hardcode calls to `arm-linux-*` rather than respecting `$CC` or `$CROSS_COMPILE`.  
> Creating symlinks in the Linaro `bin` directory maps these calls to the `arm-linux-gnueabihf-*` hard-float toolchain required for the Kobo Clara Colour's Cortex-A53 SoC without modifying legacy scripts.

```bash
KOBOLABS=
TOOL_BIN=<Where_the_path_is>/toolchain/gcc-linaro-arm-linux-gnueabihf-4.8-2013.04-20130417_linux/bin

ln -sf $TOOL_BIN/arm-linux-gnueabihf-gcc $TOOL_BIN/arm-linux-gcc
ln -sf $TOOL_BIN/arm-linux-gnueabihf-g++ $TOOL_BIN/arm-linux-g++
ln -sf $TOOL_BIN/arm-linux-gnueabihf-cpp $TOOL_BIN/arm-linux-cpp
ln -sf $TOOL_BIN/arm-linux-gnueabihf-ar $TOOL_BIN/arm-linux-ar

ln -sf $TOOL_BIN/arm-linux-gnueabihf-ranlib $TOOL_BIN/arm-linux-ranlib
ln -sf $TOOL_BIN/arm-linux-gnueabihf-nm $TOOL_BIN/arm-linux-nm
ln -sf $TOOL_BIN/arm-linux-gnueabihf-ld $TOOL_BIN/arm-linux-ld
ln -sf $TOOL_BIN/arm-linux-gnueabihf-as $TOOL_BIN/arm-linux-as

ln -sf $TOOL_BIN/arm-linux-gnueabihf-strip $TOOL_BIN/arm-linux-strip
ln -sf $TOOL_BIN/arm-linux-gnueabihf-objdump $TOOL_BIN/arm-linux-objdump
ln -sf $TOOL_BIN/arm-linux-gnueabihf-objcopy $TOOL_BIN/arm-linux-objcopy
ln -sf $TOOL_BIN/arm-linux-gnueabihf-gdump $TOOL_BIN/arm-linux-gdump
ln -sf $TOOL_BIN/arm-linux-gnueabihf-readelf $TOOL_BIN/arm-linux-readelf

```

---

### 01. OpenSSL - Documentation Build Error (`pod2man`)

> [!IMPORTANT]
> Modern `pod2man` versions reject obsolete formatting in OpenSSL 0.9.8 `.pod` files, which breaks the build.
> Changing `make install` to `make install_sw` in `./build/scripts/openssl.sh` skips documentation generation and installs software binaries only.

---

### 02. GLib (`glib.sh`)

> [!IMPORTANT]
> **Issue (ARM Instruction Set Clash):**  
> On modern GCC releases for ARM, compiling certain atomic primitives in `glib-2.22.0` fails if the toolchain attempts to emit Thumb instructions or target older CPU architectures.  
> 
> 
> **Fix:**  
> The architecture flags `-marm -march=armv7-a` were added to `CFLAGS` within `glib.sh` to enforce the emission of 32-bit ARM instructions compatible with the target e-reader architecture.  
> 
> 

```bash
#!/bin/bash
set -e -u
ARCHIVE=glib-2.22.0.tar.bz2
ARCHIVEDIR=glib-2.22.0
. $KOBO_SCRIPT_DIR/build-common.sh

pushd $ARCHIVEDIR
	( cat <<EOF
glib_cv_stack_grows=yes
ac_cv_func_posix_getpwuid_r=yes
ac_cv_func_posix_getgrgid_r=yes
glib_cv_uscore=yes
EOF
	) > glib.config.cache

	CFLAGS="${CFLAGS} -marm -march=armv7-a" LDFLAGS="${LDFLAGS}" LIBS="-liconv" ./configure --prefix=/${DEVICEROOT} --host=${CROSSTARGET} --disable-man --disable-gtk-doc --disable-silent-rules --cache=glib.config.cache --disable-static --with-libiconv=gnu
	$MAKE -j$MAKE_JOBS
	$MAKE install

	cp glibconfig.h /${DEVICEROOT}/include
popd

markbuilt

```

---

### 03. JPEG Sources (`jpegsrc.sh`)

> [!IMPORTANT]
> **Issue (Antiquated `ltconfig` Failure):**  
> The outdated `ltconfig` (1998) bundled with `jpeg-6b` fails to recognise standard `--host` flags passed by modern Autotools.  
> 
> 
> **Fix:**  
> The `jpegsrc.sh` script was rewritten to pass cross-compilation compiler variables (`CC`, `AR`, `RANLIB`) explicitly and execute `./ltconfig ./ltmain.sh ${CROSSTARGET}` manually if `./libtool` is not generated.  
> 
> 

```bash
#!/bin/bash
set -e -u
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

```

---


### 04. BusyBox (`busybox.sh`)

> [!IMPORTANT]
> **Issue (Type Conflict on `struct sysinfo`):**  
> `busybox-1.17.1` declares a redundant `struct sysinfo` in `include/libbb.h` that conflicts directly with header definitions in `sys/sysinfo.h` provided by modern glibc toolchains.  
> **Fix:**  
> A dedicated patch (`busybox-1.17.1-sysinfo.patch`) was added to `${PATCHESDIR}` to resolve the conflict.  
```diff
--- busybox-1.17.1/networking/tcpudp.c
+++ busybox-1.17.1/networking/tcpudp.c
@@ -31,3 +31,4 @@
 #include "libbb.h"
 /* Wants <limits.h> etc, thus included after libbb.h: */
+#define _LINUX_SYSINFO_H
 #include <linux/types.h> /* for __be32 etc */
 #include <linux/netfilter_ipv4.h>
```
> 
> Even so, a fallback check was implemented in `busybox.sh`:   
>  
> - If `include/libbb.h` does not contain the `#include <sys/sysinfo.h>` header after patching...
> - `sed` commands run conditionally to inject the header
> - Defining `_LINUX_SYSINFO_H`
> - And removing the obsolete `struct sysinfo` declaration



```bash
#!/bin/bash
set -e -u
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

```

---

### 05. Attr (`attr.sh`)

> [!IMPORTANT]
> **Issue (Libtool `--tag=CC` Missing Error):**  
> During the build and installation phases of `attr-2.4.43`, `libtool` aborts because it is invoked without a language tag on modern host environments.  
> 
> **Fix:**  
> The `--tag=CC` flag was explicitly appended to the `LIBTOOL` variable when invoking `./configure` as well as during `$MAKE install`, `$MAKE install-dev`, and `$MAKE install-lib` calls.
> 
> 

```bash
#!/bin/bash
set -e -u
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

```

---

### 06. LibMNG (`libmng.sh`)

> [!IMPORTANT]
> **Issue (Obsolete Autotools Macros):**
> The `configure.in` script in `libmng-1.0.10` contains deprecated macros such as `AM_C_PROTOTYPES`, causing `autogen.sh` to fail on modern Autoconf/Automake versions.
> 
> 
> **Fix:**
> The script copies build tools from the `unmaintained/` directory, strips the obsolete `AM_C_PROTOTYPES` macro from `configure.in`, and replaces `AM_PROG_LIBTOOL` with `LT_INIT` via `sed` prior to running `autogen.sh`.
> 
> 

```bash
#!/bin/bash
set -e -u
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

```

---

### 07. Qt Embedded 4.6.2 (`qt.sh`)

> [!IMPORTANT]
> **Compilation Issues & Fixes Overview:**  
> 1. **JavaScriptCore / WebKit C++11 Template Lookup Failure:**  
> * **Issue:** Under GCC 4.8+ and strict C++11 rules, unqualified base-template calls inside `PtrAndFlags.h` fail during compilation (`'set' was not declared in this scope`).  
> Modern GCC requires explicit two-phase name lookup for base class template members.  
>
> * **Fix:** A `find` + `sed` inline replacement patches `PtrAndFlags.h`, prepending `this->` to force dependent name resolution (`this->set(ptr);`).  
> 
> 
> 2. **Custom Target Profile Configuration (`qconfig-kobo.h`):**  
> * **Issue:** Qt requires a configuration profile to enable or strip core internal features via macro definitions (`#define QT_NO_...`) to reduce binary footprint on embedded devices.  
>  
> * **Fix:** The distribution profile `qconfig-dist.h` is copied to `qconfig-kobo.h`, and `-qconfig kobo` is supplied to `./configure`.  
>   
>   
> 3. **Architecture & Compiler Tolerance (`qmake.conf`):**  
> * **Issue:** Legacy 2009/2010 Qt C++ code contains pointer conversion patterns rejected by modern compilers.  
> Furthermore, certain ARM toolchain defaults build in Thumb mode, causing instruction alignment errors in Qt graphics renderers.  
>  
> * **Fix:** Appended `-marm` (forces full 32-bit ARM instruction set) and `-fpermissive` (downgrades legacy C++ syntax errors to warnings) to `QMAKE_CFLAGS` and `QMAKE_CXXFLAGS` in `mkspecs/qws/linux-arm-g++/qmake.conf`.
> 
> 
> 4. **Host Installation Prefix & Permission Denied:**  
> * **Issue:** By default, Qt `./configure` targets `/usr/local/Trolltech/QtEmbedded-4.6.2-arm/`, which triggers `Permission denied` errors when compiling without root privileges.  
> * **Fix:** Explicitly passed `-prefix ${DEVICEROOT}` (and `${QT_EXTRA_ARGS}`) to redirect build outputs into the user's isolated target Sysroot directory.  
>   
>   
> 5. **System Resource Trimming & Embedded Optimisation:**  
> * **Issue:** Default Qt builds include unnecessary desktop sub-systems (X11 extensions, printer services, desktop dialogs, mouse drivers) that bloat image size and consume CPU/RAM on e-Ink hardware.  
>  
> * **Fix (`./configure` Flags):**  
>  
> * **Desktop & Peripheral Removal:** Disables printing (`-no-feature-PRINTER`, `-no-cups`), file dialogs (`-no-feature-FILEDIALOG`), accessibility tools (`-no-accessibility`), and all X11 modules (`-no-xshape`, `-no-xrandr`, `-no-xkb`, `-no-xinerama`, `-no-xcursor`, `-no-sm`).  
>  
> * **Input Drivers:** Strips standard mouse and touchscreen drivers (`-no-mouse-*`) in favour of direct Linux framebuffer input (`-qt-gfx-linuxfb`) and hardware display rotation (`-qt-gfx-transformed`).  
>  
> * **Shared System Libraries:** Links dynamically against Sysroot PNG, JPEG, MNG, OpenSSL (`-openssl -lrt`), and D-Bus (`-dbus -ldbus-1 -I${DEVICEROOT}/include/dbus-1.0`) instead of building obsolete bundled third-party libraries.  
>  
> 

```bash
#!/bin/bash
set -e -u
ARCHIVE=qt-everywhere-opensource-src-4.6.2.tar.gz
ARCHIVEDIR=qt-everywhere-opensource-src-4.6.2
. $KOBO_SCRIPT_DIR/build-common.sh

patch -d $ARCHIVEDIR -p0 < $PATCHESDIR/qt-everywhere-opensource-src-4.6.2_kobo.patch

pushd $ARCHIVEDIR
    # Create custom Kobo target profile from default distribution profile
    cp src/corelib/global/qconfig-dist.h src/corelib/global/qconfig-kobo.h

    # Fix for C++11 template lookup in JavaScriptCore / WebKit
    find src/3rdparty/ -name "PtrAndFlags.h" -exec sed -i 's/set(ptr);/this->set(ptr);/g' {} +

    # Enforce 32-bit ARM instruction set and allow permissive C++ syntax for modern GCC
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

```

