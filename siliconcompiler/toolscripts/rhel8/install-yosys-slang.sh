#!/bin/bash

set -ex

# Get directory of script
src_path=$(cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P)/..

# yosys-slang requires C++20 (set in its CMakeLists.txt) and CMake >= 3.20.
# RHEL 8's default GCC 8 does not support C++20, so we build with
# gcc-toolset-13. cmake is installed via pip venv (same as rhel9) for a
# pinned version and to avoid dependency on the system cmake.
#
# yosys-slang is a Yosys plugin: it calls yosys-config at configure time to
# find Yosys include/lib paths. Yosys (install-yosys.sh) must be installed
# and present on PATH before running this script.
sudo yum install -y git gcc-toolset-13

mkdir -p deps
cd deps

python3 -m venv .yosys-slang --clear
. .yosys-slang/bin/activate
python3 -m pip install cmake==3.31.6

git clone $(python3 ${src_path}/_tools.py --tool yosys-slang --field git-url) yosys-slang
cd yosys-slang
git checkout $(python3 ${src_path}/_tools.py --tool yosys-slang --field git-commit)
git submodule update --init --recursive

# Build under gcc-toolset-13 for C++20 support.
scl run gcc-toolset-13 "make -j${NPROC:-$(nproc)}"

USE_SUDO_INSTALL="${USE_SUDO_INSTALL:-yes}"
if [ "${USE_SUDO_INSTALL:-yes}" = "yes" ]; then
    SUDO_INSTALL="sudo -E PATH=$PATH"
else
    SUDO_INSTALL=""
fi

$SUDO_INSTALL make install
cd -

# Copy any gcc-toolset-13 runtime libraries that the built plugin actually
# links against into PREFIX/lib so /cad/sc-tools stays self-contained.
# cp -a -n (no-clobber) avoids downgrading a newer lib already placed there
# by another tool (e.g. install-yosys.sh).
if [ ! -z ${PREFIX} ]; then
    $SUDO_INSTALL mkdir -p "${PREFIX}/lib"
    for lib in $(ldd "${PREFIX}/lib/yosys/plugin-slang.so" 2>/dev/null \
                 | awk '{print $3}' \
                 | grep '^/opt/rh/gcc-toolset-13' || true); do
        echo "Copying toolset dependency: $lib"
        $SUDO_INSTALL cp -a -n "$lib"* "${PREFIX}/lib/"
    done
fi
