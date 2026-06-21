#!/bin/bash

set -ex

# Get directory of script
src_path=$(cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P)/..

# Yosys v0.66 requires a C++20-capable compiler. RHEL 8's default GCC 8 is too
# old, so build with gcc-toolset-13 (GCC 13 has full C++20 support; same
# approach as install-surelog.sh).
# Refs: https://github.com/YosysHQ/yosys/releases/tag/v0.66
#       https://github.com/YosysHQ/yosys/blob/v0.66/README.md
sudo yum group install -y "Development Tools"
sudo yum install -y gcc-toolset-13

# tcl-devel / libffi-devel / boost-devel live in the PowerTools (a.k.a. devel)
# repo on Rocky/RHEL 8; enable it temporarily for the dev headers.
sudo dnf config-manager --set-enabled powertools 2>/dev/null || \
    sudo dnf config-manager --set-enabled devel 2>/dev/null || true
sudo yum install -y bison flex readline-devel gawk \
    tcl-devel libffi-devel zlib-devel boost-devel \
    pkgconfig git
sudo dnf config-manager --set-disabled powertools 2>/dev/null || \
    sudo dnf config-manager --set-disabled devel 2>/dev/null || true

mkdir -p deps
cd deps

# Yosys v0.66 requires bison >= 3.6; Rocky 8 AppStream ships 3.0.4.
if ! bison --version 2>/dev/null | head -1 | grep -qE '3\.([6-9]|[0-9]{2,})|[4-9]\.'; then
    BISON_PREFIX="${PREFIX:-$HOME/.local}/bison"
    if [ ! -x "${BISON_PREFIX}/bin/bison" ]; then
        curl -sSL -O https://ftp.gnu.org/gnu/bison/bison-3.8.2.tar.xz
        tar xf bison-3.8.2.tar.xz
        cd bison-3.8.2
        ./configure --prefix="$BISON_PREFIX"
        make -j${NPROC:-$(nproc)}
        make install
        cd ..
    fi
    export PATH="${BISON_PREFIX}/bin:$PATH"
fi

git clone $(python3 ${src_path}/_tools.py --tool yosys --field git-url) yosys
cd yosys
git checkout $(python3 ${src_path}/_tools.py --tool yosys --field git-commit)
git submodule update --init --recursive

USE_SUDO_INSTALL="${USE_SUDO_INSTALL:-yes}"
if [ "${USE_SUDO_INSTALL:-yes}" = "yes" ]; then
    SUDO_INSTALL=sudo
else
    SUDO_INSTALL=""
fi

scl run gcc-toolset-13 "make -j${NPROC:-$(nproc)} PREFIX=\"$PREFIX\""
$SUDO_INSTALL make install PREFIX="$PREFIX"
cd -

# Copy gcc-toolset-13's libstdc++ into the install prefix so that the yosys
# binary can find it via the existing LD_LIBRARY_PATH=/cad/sc-tools/lib,
# without requiring a global scl enable or touching the system libstdc++.
# This keeps /cad/sc-tools self-contained and isolated from commercial EDA tools.
if [ ! -z ${PREFIX} ]; then
    $SUDO_INSTALL mkdir -p "${PREFIX}/lib"
    
    # Automatically find and copy ALL runtime libraries from gcc-toolset-13 
    # that the compiled yosys binary actually dynamically links against.
    # Use cp -n (no clobber) to avoid overwriting newer libraries that
    # might have been installed by other sc-tools compiled with an even
    # newer compiler toolset.
    for lib in $(ldd "${PREFIX}/bin/yosys" | awk '{print $3}' | grep '^/opt/rh/gcc-toolset-13' || true); do
        echo "Copying toolset dependency: $lib"
        $SUDO_INSTALL cp -a -n "$lib"* "${PREFIX}/lib/"
    done
fi
