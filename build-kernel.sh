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

# Parse command line arguments
INTERACTIVE=1
while getopts "y" opt; do
    case $opt in
        y)
            INTERACTIVE=0
            ;;
        \?)
            error "Invalid option: -$OPTARG"
            ;;
    esac
done

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    error "Please don't run as root"
fi

# Configuration
CONFIG="nord4"
ANYKERNEL_BRANCH="gki-2.0"
WORKING_DIR="$(pwd)/$CONFIG"
KERNELSU_VERSION="main"

# Check for required tools
REQUIRED_TOOLS="git curl make gcc bc bison flex perl zip python3"
for tool in $REQUIRED_TOOLS; do
    if ! command -v $tool >/dev/null 2>&1; then
        error "$tool is required but not installed. Please install it first."
    fi
done

# Clean up function
cleanup() {
    log "Cleaning up previous build artifacts..."
    rm -rf "$WORKING_DIR"
    rm -rf AnyKernel3
    rm -rf git-repo
    rm -f *.zip
}

# Handle cleanup based on interactive mode
if [ -d "$WORKING_DIR" ]; then
    if [ $INTERACTIVE -eq 1 ]; then
        read -p "Previous build directory found. Clean and start fresh? [Y/n] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
            cleanup
        fi
    else
        cleanup
    fi
fi

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
git clone https://github.com/tiann/KernelSU -b main KernelSU
cd KernelSU
rm -f kernel/kernel

# Set KernelSU version and configuration
log "Configuring KernelSU..."
sed -i 's/ccflags-y += -DKSU_VERSION=16/ccflags-y += -DKSU_VERSION=12321/' kernel/Makefile

# Create symlink in kernel tree
cd ..
ln -sf $(pwd)/KernelSU/kernel $(pwd)/common/drivers/kernelsu
echo "obj-y += kernelsu/" >> ./common/drivers/Makefile

# Add KernelSU Kconfig
echo "source \"drivers/kernelsu/Kconfig\"" >> ./common/drivers/Kconfig

# Add KernelSU configuration
log "Adding KernelSU configuration..."
echo "CONFIG_KSU=y" >> ./common/arch/arm64/configs/gki_defconfig

# Apply version and build modifications
log "Applying version and build modifications..."
sed -i 's/check_defconfig//' ./common/build.config.gki
sed -i '$s|echo "$res"|echo "$res-KernelSU"|' ./common/scripts/setlocalversion
sed -i "/stable_scmversion_cmd/s/-maybe-dirty//g" ./build/kernel/kleaf/impl/stamp.bzl
sed -i 's/-dirty//' ./common/scripts/setlocalversion
perl -pi -e 's{UTS_VERSION="\$\(echo \$UTS_VERSION \$CONFIG_FLAGS \$TIMESTAMP \| cut -b -\$UTS_LEN\)"}{UTS_VERSION="#1 SMP PREEMPT Sat Apr 20 04:20:00 UTC 2024"}' ./common/scripts/mkcompile_h

# Prepare build environment
log "Setting up build environment..."
cd ..
rm -rf ./kernel_platform/common/android/abi_gki_protected_exports_*
git config --global user.email "local-build@localhost"
git config --global user.name "Local Build"

# Build the kernel
log "Building the kernel..."
cd kernel_platform/oplus/build
if [ $INTERACTIVE -eq 1 ]; then
    ./oplus_build_kernel.sh pineapple gki
else
    echo -e "pineapple\ngki" | ./oplus_build_kernel.sh
fi

# Create final ZIP
log "Creating final ZIP..."
cd ../../../
cp ./out/dist/Image ../../AnyKernel3/Image
cd ../../AnyKernel3
zip -r9 "../Anykernel3-OPNord4-A15-6.1-KernelSU.zip" ./*

cd ..
success "Build completed! Check Anykernel3-OPNord4-A15-6.1-KernelSU.zip"
