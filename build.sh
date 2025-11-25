#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd ../u-boot || { echo "Could not find u-boot dir"; exit 1; }
git reset --hard origin/master
git clean -fd
for f in "${SCRIPT_DIR}"/patches/*.patch; do
  echo "Applying patch: $f"
  git apply "$f" || { echo "Failed to apply patch: $f"; exit 1; }
done
make rpi_arm64_defconfig
make CROSS_COMPILE=aarch64-none-elf- HOSTCFLAGS="-I$(brew --prefix openssl)/include" HOSTLDFLAGS="-L$(brew --prefix openssl)/lib"
cd - || { echo "Could not return to dir"; exit 1; }
