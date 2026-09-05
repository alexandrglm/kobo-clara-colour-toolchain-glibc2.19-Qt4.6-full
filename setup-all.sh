#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to sanitize user input paths (strip trailing slashes)
clean_path() {
    local path="$1"
    echo "${path%/}"
}

# Function to validate if a given path contains a functional cross-toolchain
validate_toolchain() {
    local tc_path="$1"
    if [ -d "$tc_path" ] && [ -d "$tc_path/bin" ]; then
        local gcc_bin
        gcc_bin=$(find "$tc_path/bin" -maxdepth 1 -name "*-gcc" ! -name "arm-linux-gcc" | head -n 1)
        if [ -n "$gcc_bin" ] && [ -x "$gcc_bin" ]; then
            return 0
        fi
    fi
    return 1
}

echo "=== [1/8] Synchronising Fixes & Overrides ==="

FIXES_DIR="$SCRIPT_DIR/bootstrap2026"

if [ -n "$FIXES_DIR" ]; then
    if [ -d "$FIXES_DIR/build" ]; then
        mkdir -p "$SCRIPT_DIR/build"
        cp -rf "$FIXES_DIR/build/"* "$SCRIPT_DIR/build/"
        echo " -> Applied build overrides from $FIXES_DIR/build"
    fi

    if [ -d "$FIXES_DIR/patches" ]; then
        mkdir -p "$SCRIPT_DIR/patches"
        cp -rf "$FIXES_DIR/patches/"* "$SCRIPT_DIR/patches/"
        echo " -> Applied patch overrides from $FIXES_DIR/patches"
    fi
fi

# Ensure all scripts are executable
chmod +x "$SCRIPT_DIR/build"/*.sh 2>/dev/null || true
if [ -d "$SCRIPT_DIR/build/scripts" ]; then
    chmod +x "$SCRIPT_DIR/build/scripts"/*.sh 2>/dev/null || true
fi

echo ""
echo "=== [2/8] Base Directory Selection ==="
DEFAULT_KOBOLABS="$(cd "$SCRIPT_DIR/../" && pwd)"
read -rp "Enter base KoboLabs directory [$DEFAULT_KOBOLABS]: " KOBOLABS_INPUT
KOBOLABS_INPUT="${KOBOLABS_INPUT:-$DEFAULT_KOBOLABS}"
KOBOLABS="$(clean_path "$KOBOLABS_INPUT")"

echo ""
echo "=== [3/8] Repository Location ==="
DEFAULT_REPO_DIR="$SCRIPT_DIR"
read -rp "Enter Kobo-Reader repository location [$DEFAULT_REPO_DIR]: " REPO_DIR_INPUT
REPO_DIR_INPUT="${REPO_DIR_INPUT:-$DEFAULT_REPO_DIR}"
REPO_DIR="$(clean_path "$REPO_DIR_INPUT")"

if [ ! -d "$REPO_DIR" ]; then
    echo "[-] Error: Repository directory '$REPO_DIR' does not exist."
    exit 1
fi

echo ""
echo "=== [4/8] Sysroot (DEVICEROOT) & Temp Directories ==="
DEFAULT_DEVICEROOT="$KOBOLABS/fs"
read -rp "Enter final installation / sysroot directory (DEVICEROOT) [$DEFAULT_DEVICEROOT]: " DEVICEROOT_INPUT
DEVICEROOT_INPUT="${DEVICEROOT_INPUT:-$DEFAULT_DEVICEROOT}"
DEVICEROOT="$(clean_path "$DEVICEROOT_INPUT")"
mkdir -p "$DEVICEROOT"
mkdir -p "$DEVICEROOT/lib"
mkdir -p "$DEVICEROOT/include"
mkdir -p "$DEVICEROOT/bin"

DEFAULT_TMPDIR="$KOBOLABS/tmp"
read -rp "Enter temporary build directory (TMPDIR) [$DEFAULT_TMPDIR]: " TMPDIR_INPUT
TMPDIR_INPUT="${TMPDIR_INPUT:-$DEFAULT_TMPDIR}"
TMPDIR="$(clean_path "$TMPDIR_INPUT")"
mkdir -p "$TMPDIR"

echo ""
echo "=== [5/8] Packages & Patches Directories ==="
DEFAULT_ARCHIVESDIR="$REPO_DIR/packages"
read -rp "Enter packages archive directory (ARCHIVESDIR) [$DEFAULT_ARCHIVESDIR]: " ARCHIVESDIR_INPUT
ARCHIVESDIR_INPUT="${ARCHIVESDIR_INPUT:-$DEFAULT_ARCHIVESDIR}"
ARCHIVESDIR="$(clean_path "$ARCHIVESDIR_INPUT")"

DEFAULT_PATCHESDIR="$REPO_DIR/patches"
read -rp "Enter patches directory (PATCHESDIR) [$DEFAULT_PATCHESDIR]: " PATCHESDIR_INPUT
PATCHESDIR_INPUT="${PATCHESDIR_INPUT:-$DEFAULT_PATCHESDIR}"
PATCHESDIR="$(clean_path "$PATCHESDIR_INPUT")"

echo ""
echo "=== [6/8] Toolchain Decompression & Validation ==="
DEFAULT_TOOLCHAIN_DIR="$REPO_DIR/toolchain"
read -rp "Enter toolchain directory [$DEFAULT_TOOLCHAIN_DIR]: " TOOLCHAIN_DIR_INPUT
TOOLCHAIN_DIR_INPUT="${TOOLCHAIN_DIR_INPUT:-$DEFAULT_TOOLCHAIN_DIR}"
TOOLCHAIN_DIR="$(clean_path "$TOOLCHAIN_DIR_INPUT")"

mkdir -p "$TOOLCHAIN_DIR"
cd "$TOOLCHAIN_DIR"

# Decompress all toolchain archives found in the folder without stopping on errors
for archive in gcc-*.tar.bz2 gcc-*.tar.xz gcc-*.tar.gz gcc-*.bin; do
    [ -e "$archive" ] || continue

    # Ignore macOS/Darwin binaries if present
    if [[ "$archive" == *"darwin"* ]]; then
        echo "[-] Skipping non-Linux archive: $archive"
        continue
    fi

    case "$archive" in
        *.tar.bz2)
            target_dir="${archive%.tar.bz2}"
            if [ ! -d "$target_dir" ]; then
                echo "[+] Attempting to decompress $archive..."
                mkdir -p "$target_dir"
                if ! tar -xjvf "$archive" -C "$target_dir" --strip-components=1; then
                    echo "[-] Warning: Failed to extract $archive. Cleaning up..."
                    rm -rf "$target_dir"
                fi
            fi
            ;;
        *.tar.xz)
            target_dir="${archive%.tar.xz}"
            if [ ! -d "$target_dir" ]; then
                echo "[+] Attempting to decompress $archive..."
                mkdir -p "$target_dir"
                if ! tar -xJvf "$archive" -C "$target_dir" --strip-components=1; then
                    echo "[-] Warning: Failed to extract $archive. Cleaning up..."
                    rm -rf "$target_dir"
                fi
            fi
            ;;
        *.tar.gz)
            target_dir="${archive%.tar.gz}"
            if [ ! -d "$target_dir" ]; then
                echo "[+] Attempting to decompress $archive..."
                mkdir -p "$target_dir"
                if ! tar -xzvf "$archive" -C "$target_dir" --strip-components=1; then
                    echo "[-] Warning: Failed to extract $archive. Cleaning up..."
                    rm -rf "$target_dir"
                fi
            fi
            ;;
        *.bin)
            target_dir="${archive%.bin}"
            if [ ! -d "$target_dir" ]; then
                echo "[+] Installing/Extracting $archive..."
                chmod +x "$archive"
                ./"$archive" -i silent || ./"$archive" --mode unattended || true
            fi
            ;;
    esac
done

cd "$REPO_DIR"

# Scan for valid toolchains only (Directories containing executable bin/*-gcc)
valid_toolchains=()
for d in "$TOOLCHAIN_DIR"/*/; do
    [ -d "$d" ] || continue
    d_clean="$(clean_path "$d")"
    if validate_toolchain "$d_clean"; then
        valid_toolchains+=("$d_clean")
    else
        echo "[-] Skipping invalid or incomplete toolchain: $(basename "$d_clean")"
    fi
done

echo ""
echo "Select the toolchain to use:"
idx=1
for tc in "${valid_toolchains[@]}"; do
    echo "  $idx) Local: $(basename "$tc")"
    idx=$((idx + 1))
done

CUSTOM_OPTION=$idx
echo "  $CUSTOM_OPTION) Specify external/custom Toolchain path"

echo ""
read -rp "Enter choice [1-$CUSTOM_OPTION]: " choice

SELECTED_TOOLCHAIN_PATH=""

if [ "$choice" -eq "$CUSTOM_OPTION" ]; then
    read -rp "Enter absolute path to external toolchain: " user_path
    eval user_path="$user_path"
    user_path="$(clean_path "$user_path")"
    if validate_toolchain "$user_path"; then
        SELECTED_TOOLCHAIN_PATH="$user_path"
    else
        echo "[-] Error: Specified directory '$user_path' is not a valid toolchain (missing working bin/*-gcc)."
        exit 1
    fi
elif [ "$choice" -ge 1 ] && [ "$choice" -lt "$CUSTOM_OPTION" ] 2>/dev/null; then
    SELECTED_TOOLCHAIN_PATH="${valid_toolchains[$((choice - 1))]}"
else
    echo "[-] Error: Invalid selection."
    exit 1
fi

TOOL_BIN="$SELECTED_TOOLCHAIN_PATH/bin"
echo "[+] Selected Toolchain Binary Directory: $TOOL_BIN"

# Detect toolchain compiler prefix dynamically (ignoring generic symlinks)
COMPILER_BIN=$(find "$TOOL_BIN" -maxdepth 1 -type f -name "*-gcc" ! -name "arm-linux-gcc" | head -n 1)
if [ -z "$COMPILER_BIN" ]; then
    COMPILER_BIN=$(find "$TOOL_BIN" -maxdepth 1 -name "*-gcc" ! -name "arm-linux-gcc" | head -n 1)
fi

PREFIX_NAME=$(basename "$COMPILER_BIN" | sed 's/gcc$//')

echo ""
echo "=== [7/8] Creating Toolchain Compatibility Symlinks ==="
pushd "$TOOL_BIN" >/dev/null
    rm -f arm-linux-gcc arm-linux-g++ arm-linux-cpp arm-linux-ar \
          arm-linux-ranlib arm-linux-nm arm-linux-ld arm-linux-as \
          arm-linux-strip arm-linux-objdump arm-linux-objcopy arm-linux-readelf

    if [ "$PREFIX_NAME" != "arm-linux-" ]; then
        ln -sf "${PREFIX_NAME}gcc" arm-linux-gcc
        ln -sf "${PREFIX_NAME}g++" arm-linux-g++
        ln -sf "${PREFIX_NAME}cpp" arm-linux-cpp
        ln -sf "${PREFIX_NAME}ar" arm-linux-ar
        ln -sf "${PREFIX_NAME}ranlib" arm-linux-ranlib
        ln -sf "${PREFIX_NAME}nm" arm-linux-nm
        ln -sf "${PREFIX_NAME}ld" arm-linux-ld
        ln -sf "${PREFIX_NAME}as" arm-linux-as
        ln -sf "${PREFIX_NAME}strip" arm-linux-strip
        ln -sf "${PREFIX_NAME}objdump" arm-linux-objdump
        ln -sf "${PREFIX_NAME}objcopy" arm-linux-objcopy
        ln -sf "${PREFIX_NAME}readelf" arm-linux-readelf
    fi
popd >/dev/null

echo ""
echo "=== [8/8] Generating Configuration File ==="
CONFIG_USER="$SCRIPT_DIR/build/build-config-user.sh"
mkdir -p "$SCRIPT_DIR/build"

cat <<EOF > "$CONFIG_USER"
# Automatically generated by setup-all.sh
DEVICEROOT=$DEVICEROOT
TMPDIR=$TMPDIR
ARCHIVESDIR=$ARCHIVESDIR
PATCHESDIR=$PATCHESDIR

QT_EXTRA_ARGS="-prefix $DEVICEROOT"

CROSSTARGET=${PREFIX_NAME%-}
CROSS_COMPILE=$PREFIX_NAME
CC=${PREFIX_NAME}gcc
CXX=${PREFIX_NAME}g++
AR=${PREFIX_NAME}ar
RANLIB=${PREFIX_NAME}ranlib

export PATH=$TOOL_BIN:\$PATH
EOF

echo "[+] Environment successfully initialised."
echo "    Config written to: $CONFIG_USER"
echo "    You can now run: cd build && ./build-all.sh"
