#!/bin/bash

set -ex

# Get directory of script
src_path=$(cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P)/..

if [ ! -z ${PREFIX} ]; then
    install_loc="$PREFIX"
else
    install_loc="$HOME/.local"
fi

USE_SUDO_INSTALL="${USE_SUDO_INSTALL:-yes}"
if [ "${USE_SUDO_INSTALL:-yes}" = "yes" ]; then
    SUDO_INSTALL="sudo"
else
    SUDO_INSTALL=""
fi

# The CentOS_8 KLayout RPM links against Python 3.6, which cannot import
# SiliconCompiler's schema (functools.cache requires Python 3.9+). Build from
# source and link KLayout against a newer system Python instead.
PYTHON=""
for py in python3.12 python3.11 python3.9 python3; do
    if command -v "$py" >/dev/null 2>&1 && \
            "$py" -c 'import sys; exit(0 if sys.version_info >= (3, 9) else 1)'; then
        PYTHON="$py"
        break
    fi
done
if [ -z "$PYTHON" ]; then
    echo "KLayout source build requires Python >= 3.9 for SiliconCompiler compatibility" >&2
    exit 1
fi

python_devel="${PYTHON}-devel"
if ! rpm -q "$python_devel" >/dev/null 2>&1; then
    python_devel="python3-devel"
fi

sudo dnf config-manager --set-enabled powertools 2>/dev/null || \
    sudo dnf config-manager --set-enabled devel 2>/dev/null || true
sudo yum install -y gcc-toolset-13 git \
    qt5-qtbase-devel qt5-qtsvg-devel qt5-qtmultimedia-devel \
    qt5-qttools-devel qt5-qtxmlpatterns-devel \
    ruby-devel libgit2-devel \
    "$python_devel"
sudo dnf config-manager --set-disabled powertools 2>/dev/null || \
    sudo dnf config-manager --set-disabled devel 2>/dev/null || true

QMAKE=""
for candidate in qmake-qt5 qmake; do
    if command -v "$candidate" >/dev/null 2>&1; then
        QMAKE="$candidate"
        break
    fi
done
if [ -z "$QMAKE" ]; then
    echo "qmake not found; install qt5-qtbase-devel" >&2
    exit 1
fi

mkdir -p deps
cd deps

git clone "$(python3 "${src_path}/_tools.py" --tool klayout --field git-url)" klayout
cd klayout
git checkout "$(python3 "${src_path}/_tools.py" --tool klayout --field git-commit)"

build_cmd="./build.sh -prefix \"${install_loc}\" -python \"${PYTHON}\" -qmake \"${QMAKE}\" -option \"-j${NPROC:-$(nproc)}\""
if [ "${USE_SUDO_INSTALL}" = "yes" ]; then
    scl run gcc-toolset-13 "sudo -E ${build_cmd}"
else
    scl run gcc-toolset-13 "${build_cmd}"
fi

# Bundle gcc-toolset-13 runtime libraries linked by the klayout binary.
$SUDO_INSTALL mkdir -p "${install_loc}/lib"
for lib in $(ldd "${install_loc}/bin/klayout" 2>/dev/null \
             | awk '{print $3}' \
             | grep '^/opt/rh/gcc-toolset-13' || true); do
    echo "Copying toolset dependency: $lib"
    $SUDO_INSTALL cp -a -n "$lib"* "${install_loc}/lib/"
done

cd -
