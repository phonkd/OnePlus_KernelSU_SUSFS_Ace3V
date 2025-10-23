#!/bin/bash

# Export necessary variables
export ARCH=arm64
export SUBARCH=arm64
export CLANG_PATH=/root/tc/clang-r498229b/bin
export PATH=${CLANG_PATH}:${PATH}
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
export LLVM=1
export LLVM_IAS=1

# Clean build directory
make clean && make mrproper

# Set default defconfig
make vendor/ace3_defconfig

# Build the kernel
make -j$(nproc) \
    O=out \
    CC=clang \
    AR=llvm-ar \
    NM=llvm-nm \
    OBJCOPY=llvm-objcopy \
    OBJDUMP=llvm-objdump \
    STRIP=llvm-strip \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
    CLANG_TRIPLE=aarch64-linux-gnu- \
    2>&1 | tee build.log

# Check if build was successful
if [ -f out/arch/arm64/boot/Image ]; then
    echo "Kernel built successfully!"
    # Copy the kernel image to a specific location if needed
    # cp out/arch/arm64/boot/Image /path/to/destination/
else
    echo "Kernel build failed! Check build.log for errors"
    exit 1
fi
