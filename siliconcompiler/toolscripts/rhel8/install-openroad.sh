#!/bin/sh

set -ex

src_path=$(cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P)/..

USE_SUDO_INSTALL="${USE_SUDO_INSTALL:-yes}"
if [ "${USE_SUDO_INSTALL:-yes}" = "yes" ]; then
    SUDO_INSTALL="sudo -E PATH=$PATH"
else
    SUDO_INSTALL=""
fi

if [ ! -z ${PREFIX} ]; then
    install_loc="$PREFIX"
else
    install_loc="$HOME/.local"
fi

# OpenROAD's Bazel build pulls a prebuilt LLVM toolchain that requires GLIBC
# >= 2.29; Rocky/RHEL 8 ships glibc 2.28. Use the CMake path with
# gcc-toolset-13 instead (Build.md / local install flow).
#
# xcb-util-*-devel live in PowerTools; xcb-util-cursor is in EPEL.
sudo dnf config-manager --set-enabled powertools 2>/dev/null || \
    sudo dnf config-manager --set-enabled devel 2>/dev/null || true
sudo yum install -y epel-release gcc-toolset-13 git curl

mkdir -p deps
cd deps

git clone $(python3 ${src_path}/_tools.py --tool openroad --field git-url) openroad
cd openroad
git checkout $(python3 ${src_path}/_tools.py --tool openroad --field git-commit)
git submodule update --init --recursive

# RPM packages (Qt, Tcl, yaml-cpp, ...) plus common deps (boost, or-tools, ...).
sudo ./etc/DependencyInstaller.sh -base
./etc/DependencyInstaller.sh -common -prefix="$install_loc"

sudo dnf config-manager --set-disabled powertools 2>/dev/null || \
    sudo dnf config-manager --set-disabled devel 2>/dev/null || true

# OpenROAD requires C++20; Build.sh only auto-enables devtoolset-8, not
# gcc-toolset-13, so run the build under the toolset explicitly.
scl run gcc-toolset-13 \
    "./etc/Build.sh -prefix=${install_loc} -threads=${NPROC:-$(nproc)} -clean"
scl run gcc-toolset-13 "cmake --install build"

# Bundle gcc-toolset-13 runtime libraries linked by the openroad binary.
$SUDO_INSTALL mkdir -p "${install_loc}/lib"
for lib in $(ldd "${install_loc}/bin/openroad" 2>/dev/null \
             | awk '{print $3}' \
             | grep '^/opt/rh/gcc-toolset-13' || true); do
    echo "Copying toolset dependency: $lib"
    $SUDO_INSTALL cp -a -n "$lib"* "${install_loc}/lib/"
done

cd -
