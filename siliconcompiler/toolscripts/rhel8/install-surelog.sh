#!/bin/sh

set -ex

# Get directory of script
src_path=$(cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P)/..

sudo yum install -y git

# These dependencies are up-to-date with instructions from the INSTALL.md from the commit we are pinned to below
sudo yum install -y gcc-toolset-13
sudo dnf config-manager --set-enabled devel || true
sudo yum install -y libuuid-devel java-11-openjdk-devel python3 zlib-static openssl-devel
sudo dnf config-manager --set-disabled devel || true

mkdir -p deps
cd deps

python3 -m venv .surelog --clear
. .surelog/bin/activate
python3 -m pip install cmake==3.28.4
python3 -m pip install orderedmultidict

git clone $(python3 ${src_path}/_tools.py --tool surelog --field git-url) surelog
cd surelog
git checkout $(python3 ${src_path}/_tools.py --tool surelog --field git-commit)
git submodule update --init --recursive

USE_SUDO_INSTALL="${USE_SUDO_INSTALL:-yes}"
if [ "${USE_SUDO_INSTALL:-yes}" = "yes" ]; then
    SUDO_INSTALL="sudo -E PATH=$PATH"
else
    SUDO_INSTALL=""
fi

if [ -n "$SUDO_INSTALL" ]; then
    $SUDO_INSTALL scl run gcc-toolset-13 "LDFLAGS=\"-lrt\" make -j${NPROC:-$(nproc)} install"
else
    scl run gcc-toolset-13 "LDFLAGS=\"-lrt\" make -j${NPROC:-$(nproc)} install"
fi

cd -
