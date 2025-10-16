# U-Boot for Raspberry Pi Workflow

This GitHub Actions workflow builds U-Boot for Raspberry Pi 4 and creates a complete, flashable SD card image.

## Features

- ✅ Builds U-Boot from source with custom patches
- ✅ Downloads official Raspberry Pi firmware
- ✅ Creates a complete SD card image (`.img`)
- ✅ Compresses the image with xz for smaller downloads
- ✅ Generates SHA256 checksums
- ✅ Publishes GitHub releases automatically

## Triggering the Workflow

### Manual Trigger (Workflow Dispatch)

You can manually trigger a build from the GitHub Actions tab:

1. Go to **Actions** → **U-Boot for Raspberry Pi Build**
2. Click **Run workflow**
3. Optionally specify:
   - U-Boot version (default: `v2025.10`)
   - Raspberry Pi firmware version (default: `1.20241008`)
4. Click **Run workflow**

This will build the image and upload it as an artifact (available for 30 days).

### Automatic Release

To create a GitHub release with the built image:

1. Create and push a tag with the format `uboot-v*`:

```bash
git tag uboot-v2025.10-rpi4
git push origin uboot-v2025.10-rpi4
```

2. The workflow will automatically:
   - Build U-Boot
   - Download Raspberry Pi firmware
   - Create the SD card image
   - Compress it
   - Create a GitHub release with the image attached

## Output Files

The workflow produces:

- **`rpi4-uboot-{version}-firmware-{version}.img.xz`**: Compressed SD card image
- **`rpi4-uboot-{version}-firmware-{version}.img.xz.sha256`**: Checksum file
- **Release notes**: Detailed information about the build

## SD Card Image Contents

The generated image includes:

### Boot Partition (FAT32)
- **Raspberry Pi firmware files**:
  - `bootcode.bin` - GPU bootloader
  - `start*.elf` - GPU firmware
  - `fixup*.dat` - Memory split configuration
  - `*.dtb` - Device tree blobs
  - `overlays/` - Device tree overlays
- **U-Boot**:
  - `u-boot.bin` - Custom-built U-Boot binary
- **Configuration**:
  - `config.txt` - Custom boot configuration

### Custom config.txt Features

The included `config.txt` configures:
- 64-bit ARM mode
- U-Boot as the kernel
- Minimal GPU memory (16MB)
- UART debugging enabled
- USB boot support
- Network boot ready

## Using the Image

### With Raspberry Pi Imager (Recommended)

1. Download the `.xz` file from the release
2. Open Raspberry Pi Imager
3. Choose "Use custom" and select the downloaded file
4. Select your SD card
5. Write

### With dd (Linux/macOS)

```bash
# Download and decompress
wget https://github.com/your-org/repo/releases/download/uboot-v2025.10-rpi4/rpi4-uboot-v2025.10-firmware-1.20241008.img.xz
xz -d rpi4-uboot-v2025.10-firmware-1.20241008.img.xz

# Verify checksum
sha256sum -c rpi4-uboot-v2025.10-firmware-1.20241008.img.xz.sha256

# Write to SD card (replace /dev/sdX with your SD card)
sudo dd if=rpi4-uboot-v2025.10-firmware-1.20241008.img of=/dev/sdX bs=4M status=progress
sudo sync
```

## Boot Sequence

When the Raspberry Pi boots from this image:

1. **GPU bootloader** (bootcode.bin) loads
2. **GPU firmware** (start.elf) reads config.txt
3. **U-Boot** loads as the "kernel"
4. **U-Boot executes boot command**:
   - Attempts USB disk boot (EFI)
   - Attempts network boot via DHCP/PXE
   - Falls back to local disk

## Customization

### Modifying config.txt

To customize the boot configuration:

1. Edit the `Create custom config.txt` step in the workflow
2. Modify the `config.txt` content
3. Push changes or manually trigger the workflow

### Adding Custom Boot Command

To add a custom U-Boot boot command:

1. Uncomment the "Add custom boot configuration" step
2. Modify the `CONFIG_BOOTCOMMAND` value
3. Rebuild

### Using Different Firmware Versions

Find available firmware versions at:
https://github.com/raspberrypi/firmware/releases

Specify the version when running the workflow manually.

## Troubleshooting

### Image won't boot

1. Verify the image was written correctly:
   ```bash
   sha256sum /dev/sdX
   ```
2. Check UART output (connect serial console to GPIO pins)
3. Ensure you're using a Raspberry Pi 4 or Pi 400

### Network boot not working

1. Verify DHCP server is providing:
   - IP address
   - Next-server (TFTP server IP)
   - Boot filename (for PXE)
2. Check TFTP server is serving files
3. Review the TFTP logging middleware output

### USB boot not working

1. Ensure USB device is formatted with FAT32
2. EFI boot file should be at `/EFI/BOOT/bootaa64.efi` or `/EFI/BOOT/bootx64.efi`
3. Try different USB ports

## Technical Details

### Build Environment

- **Runner**: `ubuntu-24.04-arm` (native ARM64)
- **Compiler**: `aarch64-linux-gnu-gcc`
- **Target**: `rpi_arm64_defconfig`

### Patches Applied

The workflow applies patches from `smee/internal/firmware/patches/`:
- NVMe boot support
- EFI boot improvements
- USB XHCI compatibility fixes

### Image Creation Process

1. Download Raspberry Pi firmware release
2. Extract boot files
3. Build U-Boot with patches
4. Create blank image file
5. Partition with MBR (single FAT32 partition)
6. Format partition
7. Copy all files
8. Compress with xz

## Contributing

To improve this workflow:

1. Test changes locally with `act` if possible
2. Use workflow_dispatch for testing
3. Create releases only after verification

## References

- [U-Boot Documentation](https://docs.u-boot.org/)
- [Raspberry Pi Firmware](https://github.com/raspberrypi/firmware)
- [Raspberry Pi Boot Documentation](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#raspberry-pi-4-boot-eeprom)
