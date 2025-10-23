#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log() {
    echo -e "${BLUE}[*]${NC} $1"
}

error() {
    echo -e "${RED}[!]${NC} $1"
    exit 1
}

success() {
    echo -e "${GREEN}[+]${NC} $1"
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    error "Please don't run as root"
fi

# Configuration
CONFIG="nord4"
ANYKERNEL_BRANCH="gki-2.0"
SUSFS_BRANCH="gki-android14-6.1"
WORKING_DIR="$(pwd)/$CONFIG"

# Check for required tools
REQUIRED_TOOLS="git curl make gcc bc bison flex perl zip python3"
for tool in $REQUIRED_TOOLS; do
    if ! command -v $tool >/dev/null 2>&1; then
        error "$tool is required but not installed. Please install it first."
    fi
done

# Install repo tool if not present
if [ ! -f "./git-repo/repo" ]; then
    log "Installing repo tool..."
    mkdir -p ./git-repo
    curl https://storage.googleapis.com/git-repo-downloads/repo > ./git-repo/repo
    chmod a+rx ./git-repo/repo
fi
REPO="$(pwd)/git-repo/repo"

# Clone required repositories
log "Cloning required repositories..."
if [ ! -d "AnyKernel3" ]; then
    git clone https://github.com/TheWildJames/AnyKernel3.git -b "$ANYKERNEL_BRANCH"
fi

if [ ! -d "susfs4ksu" ]; then
    git clone https://gitlab.com/simonpunk/susfs4ksu.git -b "$SUSFS_BRANCH"
fi

if [ ! -d "kernel_patches" ]; then
    git clone https://github.com/TheWildJames/kernel_patches.git
fi

# Create and enter working directory
log "Setting up working directory..."
mkdir -p "$WORKING_DIR"
cd "$WORKING_DIR"

# Initialize and sync kernel source
log "Initializing and syncing kernel source..."
$REPO init -u https://github.com/OnePlusOSS/kernel_manifest.git -b oneplus/sm7675 -m oneplus_nord_4_v.xml --repo-rev=v2.16 --depth=1
$REPO sync -c -j$(nproc --all) --no-tags --fail-fast

# Add KernelSU
log "Adding KernelSU..."
cd kernel_platform
curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next/kernel/setup.sh" | bash -
cd KernelSU-Next/kernel
sed -i 's/ccflags-y += -DKSU_VERSION=16/ccflags-y += -DKSU_VERSION=12321/' ./Makefile
cd ../..

# Apply SUSFS patches
log "Applying SUSFS patches..."
cp ../../susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch ./KernelSU-Next/
cp ../../susfs4ksu/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch ./common/
cp -r ../../susfs4ksu/kernel_patches/fs/* ./common/fs/
cp -r ../../susfs4ksu/kernel_patches/include/linux/* ./common/include/linux/

cd KernelSU-Next
patch -p1 --forward < 10_enable_susfs_for_ksu.patch || true
cd ../common
patch -p1 < 50_add_susfs_in_gki-android14-6.1.patch || true
cd ..

# Apply Next-SUSFS patches
log "Applying next SUSFS patches..."
cp ../../kernel_patches/apk_sign.c_fix.patch ./
patch -p1 -F 3 < apk_sign.c_fix.patch
cp ../../kernel_patches/core_hook.c_fix.patch ./
patch -p1 --fuzz=3 < core_hook.c_fix.patch
cp ../../kernel_patches/selinux.c_fix.patch ./
patch -p1 -F 3 < selinux.c_fix.patch

# Apply Hide Stuff patches
log "Applying hide stuff patches..."
cd common
cp ../../../kernel_patches/69_hide_stuff.patch ./
patch -p1 -F 3 < 69_hide_stuff.patch || true
cd ..

# Add SUSFS configuration settings
log "Adding SUSFS configuration..."
cat << 'EOF' >> ./common/arch/arm64/configs/gki_defconfig
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SUS_OVERLAYFS=y
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_SU=y
CONFIG_TMPFS_XATTR=y
EOF

# Run sed and perl commands
log "Applying version and build modifications..."
sed -i 's/check_defconfig//' ./common/build.config.gki
sed -i '$s|echo "$res"|echo "$res-Wild+"|' ./common/scripts/setlocalversion
sed -i "/stable_scmversion_cmd/s/-maybe-dirty//g" ./build/kernel/kleaf/impl/stamp.bzl
sed -i 's/-dirty//' ./common/scripts/setlocalversion
perl -pi -e 's{UTS_VERSION="\$\(echo \$UTS_VERSION \$CONFIG_FLAGS \$TIMESTAMP \| cut -b -\$UTS_LEN\)"}{UTS_VERSION="#1 SMP PREEMPT Sat Apr 20 04:20:00 UTC 2024"}' ./common/scripts/mkcompile_h

# Build the kernel
log "Building the kernel..."
cd ..
rm -rf ./kernel_platform/common/android/abi_gki_protected_exports_*
git config --global user.email "local-build@localhost"
git config --global user.name "Local Build"
./kernel_platform/oplus/build/oplus_build_kernel.sh pineapple gki

# Create final ZIP
log "Creating final ZIP..."
cp ./out/dist/Image ../AnyKernel3/Image
cd ../AnyKernel3
zip -r9 "../Anykernel3-OPNord4-A15-6.1-KernelSU-SUSFS.zip" ./*

cd ..
success "Build completed! Check Anykernel3-OPNord4-A15-6.1-KernelSU-SUSFS.zip"
