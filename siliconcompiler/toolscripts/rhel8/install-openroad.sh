#!/bin/sh

set -ex

src_path=$(cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P)/..

USE_SUDO_INSTALL="${USE_SUDO_INSTALL:-yes}"
if [ "${USE_SUDO_INSTALL:-yes}" = "yes" ]; then
    SUDO_INSTALL="sudo -E PATH=$PATH"
else
    SUDO_INSTALL=""
fi

sudo yum install -y git curl --skip-broken

# OpenROAD's DependencyInstaller pulls xcb GUI libs via yum. On Rocky/RHEL 8:
#   - xcb-util-*-devel live in PowerTools (CRB)
#   - xcb-util-cursor is only in EPEL (not AppStream)
sudo dnf config-manager --set-enabled powertools 2>/dev/null || \
    sudo dnf config-manager --set-enabled devel 2>/dev/null || true
sudo yum install -y epel-release

mkdir -p deps
cd deps

mkdir -p bazelbin/bin
BAZEL_PREFIX=$(pwd)/bazelbin

PATH="$BAZEL_PREFIX/bin:$PATH"

git clone $(python3 ${src_path}/_tools.py --tool openroad --field git-url) openroad
cd openroad
git checkout $(python3 ${src_path}/_tools.py --tool openroad --field git-commit)
git submodule update --init --recursive

# DependencyInstaller.sh supports RHEL/Rocky/AlmaLinux 8 (or-tools, bazel libs,
# and compiler toolchain are handled internally for the rhel8 family).
sudo ./etc/DependencyInstaller.sh -bazel -prefix="$BAZEL_PREFIX"
sudo chown -R $USER:$USER $BAZEL_PREFIX

sudo dnf config-manager --set-disabled powertools 2>/dev/null || \
    sudo dnf config-manager --set-disabled devel 2>/dev/null || true

if [ ! -z ${PREFIX} ]; then
    install_loc="$PREFIX"
else
    install_loc="$HOME/.local"
fi

bazelisk run :install --config=release --//:platform=gui -- "$install_loc"

cd -
