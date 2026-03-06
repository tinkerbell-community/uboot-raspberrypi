#!/usr/bin/env bash
# Wrapper script to run EEPROM configuration builder in Docker container
# This ensures rpi-eeprom tools are available regardless of host OS

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="rpi-eeprom-builder"

echo "=== Building Docker image with rpi-eeprom tools ==="
docker build -f "${SCRIPT_DIR}/Dockerfile.eeprom" -t "${IMAGE_NAME}" "${SCRIPT_DIR}"

echo
echo "=== Running EEPROM configuration script in container ==="
docker run --rm \
    -v "${SCRIPT_DIR}:/workspace" \
    -u "$(id -u):$(id -g)" \
    "${IMAGE_NAME}"

echo
echo "=== Output files on host ==="
ls -lh "${SCRIPT_DIR}/pieeprom.upd" 2>/dev/null || echo "Error: pieeprom.upd not created"
ls -lh "${SCRIPT_DIR}/build/eeprom/" 2>/dev/null || true
