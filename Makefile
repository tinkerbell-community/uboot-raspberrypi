# Makefile for Raspberry Pi 3/4/5 UEFI firmware build with ARM Trusted Firmware

# Board model configuration (3, 4, or 5), default to 4
MODEL ?= 4
BUILD_TYPE ?= RELEASE

# Multi-platform build support
ALL_MODELS := 4 5

# Configuration variables
PROJECT_URL := https://github.com/pftf/RPi4
ARCH := AARCH64
COMPILER := GCC5
CROSS_COMPILE ?= aarch64-elf-
GCC5_AARCH64_PREFIX ?= $(shell echo $${GCC5_AARCH64_PREFIX:-aarch64-elf-})
START_ELF_VERSION := master
DTB_VERSION := b49983637106e5fb33e2ae60d8c15a53187541e4
DTBO_VERSION := master
RPI_FIRMWARE_VERSION := master
RPI_FIRMWARE_URL := https://github.com/raspberrypi/firmware/raw/$(RPI_FIRMWARE_VERSION)/boot
BRCM_FIRMWARE_URL := https://archive.raspberrypi.org/debian/pool/main/f/firmware-nonfree/firmware-brcm80211_20240709-2~bpo12+1+rpt3_all.deb

# Version can be overridden via environment variable
VERSION ?= $(shell git describe --tags --always 2>/dev/null || echo "dev")

# Directories
WORKSPACE := $(PWD)
KEYS_DIR := keys
BUILD_DIR := Build
ARCHIVE_DIR := $(BUILD_DIR)/archive
FIRMWARE_DIR := $(BUILD_DIR)/RPi$(MODEL)/$(BUILD_TYPE)_$(COMPILER)/FV
OVERLAYS_DIR := $(ARCHIVE_DIR)/overlays
BRCM_DIR := $(ARCHIVE_DIR)/firmware
PATCHES_DIR := patches

EDK2_DIR := edk2
EDK2_PLATFORMS_DIR := edk2-platforms
ACTIVE_PLATFORM := $(EDK2_PLATFORMS_DIR)/Platform/StandaloneMm/PlatformStandaloneMmPkg/PlatformStandaloneMmRpmb.dsc

# ARM Trusted Firmware
TFA_DIR := firmware
TFA_BUILD_TYPE = $(shell echo $(BUILD_TYPE) | tr A-Z a-z)
TFA_ARTIFACTS_DIR := $(TFA_DIR)/build/rpi$(MODEL)/$(TFA_BUILD_TYPE)

OPTEE_OS_DIR := optee_os
OPTEE_OS_BUILD_DIR := $(OPTEE_OS_DIR)/build

# Find all patch files in PATCHES_DIR
PATCH_FILES := $(wildcard $(PATCHES_DIR)/*.patch)

# Generated files
ARCHIVE_FILE := RPi$(MODEL)_UEFI_Firmware_$(VERSION).zip
IMAGE_FILE := RPi$(MODEL)_UEFI_Firmware_$(VERSION).img
DMG_FILE := $(addsuffix .dmg, $(basename $(IMAGE_FILE)))
FIRMWARE_FILE := $(FIRMWARE_DIR)/RPI_EFI.fd
BRCM_DEB_FILE := $(BRCM_DIR)/$(notdir $(BRCM_FIRMWARE_URL))
BRCM_ARCHIVE := $(BRCM_DIR)/data.tar.xz

# Key files
KEY_FILES := $(KEYS_DIR)/pk.cer \
             $(KEYS_DIR)/ms_kek1.cer \
             $(KEYS_DIR)/ms_kek2.cer \
             $(KEYS_DIR)/ms_db1.cer \
             $(KEYS_DIR)/ms_db2.cer \
             $(KEYS_DIR)/ms_db3.cer \
             $(KEYS_DIR)/ms_db4.cer \
             $(KEYS_DIR)/arm64_dbx.bin

# Raspberry Pi support files
RPI_FILES := fixup4.dat \
             start4.elf \
             bcm2711-rpi-4-b.dtb \
             bcm2711-rpi-cm4.dtb \
             bcm2711-rpi-400.dtb \
			 bcm2712-rpi-5-b.dtb \
			 bcm2712-d-rpi-5-b.dtb

# Overlay files
OVERLAY_FILES := miniuart-bt.dtbo \
                 upstream-pi4.dtbo

# Broadcom firmware files
BRCM_FILES := brcmfmac43455-sdio.bin \
			  brcmfmac43455-sdio.clm_blob \
			  brcmfmac43455-sdio.txt

RPI_FILES := $(addprefix $(ARCHIVE_DIR)/, $(RPI_FILES))
OVERLAY_FILES := $(addprefix $(OVERLAYS_DIR)/, $(OVERLAY_FILES))
BRCM_FILES := $(addprefix $(BRCM_DIR)/, $(BRCM_FILES))

# Build flags
PACKAGES_PATH := $(WORKSPACE)/$(EDK2_DIR):$(WORKSPACE)/$(EDK2_PLATFORMS_DIR)
BUILD_FLAGS := -D NETWORK_ALLOW_HTTP_CONNECTIONS=TRUE \
               -D SECURE_BOOT_ENABLE=TRUE \
               -D INCLUDE_TFTP_COMMAND=TRUE \
               -D NETWORK_ISCSI_ENABLE=TRUE \
               -D SMC_PCI_SUPPORT=1
TLS_DISABLE_FLAGS := -D NETWORK_TLS_ENABLE=FALSE \
                     -D NETWORK_ALLOW_HTTP_CONNECTIONS=TRUE
DEFAULT_KEYS := -D DEFAULT_KEYS=TRUE \
                -D PK_DEFAULT_FILE=$(WORKSPACE)/$(KEYS_DIR)/pk.cer \
                -D KEK_DEFAULT_FILE1=$(WORKSPACE)/$(KEYS_DIR)/ms_kek1.cer \
                -D KEK_DEFAULT_FILE2=$(WORKSPACE)/$(KEYS_DIR)/ms_kek2.cer \
                -D DB_DEFAULT_FILE1=$(WORKSPACE)/$(KEYS_DIR)/ms_db1.cer \
                -D DB_DEFAULT_FILE2=$(WORKSPACE)/$(KEYS_DIR)/ms_db2.cer \
                -D DB_DEFAULT_FILE3=$(WORKSPACE)/$(KEYS_DIR)/ms_db3.cer \
                -D DB_DEFAULT_FILE4=$(WORKSPACE)/$(KEYS_DIR)/ms_db4.cer \
                -D DBX_DEFAULT_FILE1=$(WORKSPACE)/$(KEYS_DIR)/arm64_dbx.bin

# Default target - build all platforms (required for complete image)
.PHONY: all
all: all-platforms

# Build all platforms
.PHONY: all-platforms
all-platforms:
	@echo "Building firmware for all Raspberry Pi models..." # $(MAKE) MODEL=3 build-firmware
	$(MAKE) MODEL=4 build-firmware
	$(MAKE) MODEL=5 build-firmware
	$(MAKE) build-archive-all

# Build archive with all platform binaries
.PHONY: build-archive-all
build-archive-all: download-rpi-files setup-brcm $(ARCHIVE_DIR)/config.txt $(ARCHIVE_DIR)/Readme.md
	@echo "Creating multi-platform archive..."
	@mkdir -p $(ARCHIVE_DIR)
  ## cp Build/RPi3/$(BUILD_TYPE)_$(COMPILER)/FV/RPI_EFI.fd $(ARCHIVE_DIR)/RPI3_EFI.fd 2>/dev/null || true
	cp Build/RPi4/$(BUILD_TYPE)_$(COMPILER)/FV/RPI_EFI.fd $(ARCHIVE_DIR)/RPI4_EFI.fd 2>/dev/null || true
	cp Build/RPi5/$(BUILD_TYPE)_$(COMPILER)/FV/RPI_EFI.fd $(ARCHIVE_DIR)/RPI5_EFI.fd 2>/dev/null || true
	cd $(BUILD_DIR) && zip -r $(ARCHIVE_FILE) $(notdir $(ARCHIVE_DIR))/*
	@echo "Archive created: $(BUILD_DIR)/$(ARCHIVE_FILE)"

# Check for required tools
.PHONY: check-deps
check-deps:
	@echo "Checking dependencies..."
	@command -v openssl >/dev/null 2>&1 || { echo "Error: openssl not found"; exit 1; }
	@command -v curl >/dev/null 2>&1 || { echo "Error: curl not found"; exit 1; }
	@command -v zip >/dev/null 2>&1 || { echo "Error: zip not found"; exit 1; }
	@command -v make >/dev/null 2>&1 || { echo "Error: make not found"; exit 1; }
	@command -v sed >/dev/null 2>&1 || { echo "Error: sed not found"; exit 1; }
	@command -v grep >/dev/null 2>&1 || { echo "Error: grep not found"; exit 1; }
	@command -v git >/dev/null 2>&1 || { echo "Error: git not found"; exit 1; }
	@command -v sha256sum >/dev/null 2>&1 || { echo "Error: sha256sum not found"; exit 1; }
	@command -v $(GCC5_AARCH64_PREFIX)gcc >/dev/null 2>&1 || { echo "Error: $(GCC5_AARCH64_PREFIX)gcc not found. Install with: brew install aarch64-elf-gcc"; exit 1; }
	@command -v $(GCC5_AARCH64_PREFIX)gcc-ar >/dev/null 2>&1 || { echo "Error: $(GCC5_AARCH64_PREFIX)gcc-ar not found. Install with: brew install aarch64-elf-gcc"; exit 1; }
	@command -v iasl >/dev/null 2>&1 || { echo "Error: iasl not found. Install with: brew install acpica"; exit 1; }
	@command -v python3 >/dev/null 2>&1 || { echo "Error: python3 not found. Install Python 3.x"; exit 1; }

# Apply all patch files from PATCHES_DIR
.PHONY: apply-patches
apply-patches:
	@cd platforms && patch -s -f -p1 < ../patches/000-rpi5-edk2-platforms.patch || true

$(EDK2_DIR):
	@echo "Cloning EDK2 repository..."
	git clone --depth 1 --recurse-submodules https://github.com/tianocore/edk2.git $(EDK2_DIR)

$(EDK2_DIR)/Build/MmStandaloneRpmb/$(BUILD_TYPE)_$(COMPILER)/FV/BL32_AP_MM.fd: | $(EDK2_DIR) $(EDK2_PLATFORMS_DIR) $(TFA_DIR) setup-edk2
	@echo "Building BL32_AP_MM.fd firmware for RPi$(MODEL)..."
	export WORKSPACE=$(WORKSPACE) && \
	export PACKAGES_PATH="$(PACKAGES_PATH)" && \
	export ACTIVE_PLATFORM="$(ACTIVE_PLATFORM)" && \
	export $(COMPILER)_$(ARCH)_PREFIX="$(GCC5_AARCH64_PREFIX)" && \
	. $(EDK2_DIR)/edksetup.sh && \
	build -a $(ARCH) -t $(COMPILER) -b $(BUILD_TYPE) -p $(ACTIVE_PLATFORM)
	@echo "BL32_AP_MM.fd build complete"

build-edk2: $(EDK2_DIR)/Build/MmStandaloneRpmb/$(BUILD_TYPE)_$(COMPILER)/FV/BL32_AP_MM.fd
	@echo "EDK2 build complete"

$(EDK2_PLATFORMS_DIR):
	@echo "Cloning EDK2 Platforms repository..."
	git clone --depth 1 --recurse-submodules https://github.com/tianocore/edk2-platforms.git $(EDK2_PLATFORMS_DIR)

$(TFA_DIR):
	@echo "Cloning ARM Trusted Firmware repository..."
	git clone --depth 1 https://github.com/ARM-software/arm-trusted-firmware.git $(TFA_DIR)

$(TFA_DIR)/build/rpi$(MODEL)/$(TFA_BUILD_TYPE)/bl32.bin: | $(TFA_DIR)
	@echo "Building ARM Trusted Firmware for RPi$(MODEL)..."
	$(MAKE) -C $(TFA_DIR) \
		PLAT=rpi$(MODEL) \
    CFG_STMM_PATH=BL32_AP_MM.fd \
    CFG_ARM64_core=y \
    CFG_RPMB_FS=y \
    CFG_RPMB_FS_DEV_ID=0 CFG_CORE_HEAP_SIZE=524288 CFG_RPMB_WRITE_KEY=y \
    CFG_CORE_DYN_SHM=y CFG_RPMB_TESTKEY=y CFG_REE_FS=n \
    CFG_CORE_ARM64_PA_BITS=48 CFG_TEE_CORE_LOG_LEVEL=1 \
    CFG_TEE_TA_LOG_LEVEL=1 CFG_SCTLR_ALIGNMENT_CHECK=n \
		PRELOADED_BL33_BASE=0x20000 \
		RPI3_PRELOADED_DTB_BASE=0x1F0000 \
		SUPPORT_VFP=1 \
		SMC_PCI_SUPPORT=1 \
		DEBUG=$(if $(filter RELEASE,$(BUILD_TYPE)),0,1)
	@echo "ARM Trusted Firmware build complete"

# Set up EDK2 BaseTools
.PHONY: setup-edk2
setup-edk2:
	@echo "Setting up EDK2 BaseTools..."
	@echo "Using native macOS toolchain for BaseTools..."
	PATH="/usr/bin:/bin:/usr/sbin:/sbin" $(MAKE) -C $(EDK2_DIR)/BaseTools CC=clang CXX=clang++ AR=/usr/bin/ar RANLIB=/usr/bin/ranlib
	@echo "EDK2 BaseTools setup complete"

%-bl32.bin: %.bin
	@echo "Converting $< to $@..."
	cp $< $<-pad.tmp
	truncate --size=128K $<-pad.tmp
	@cat $<-pad.tmp $(OPTEE_OS_DIR)/out/arm-plat-rpi$(MODEL)/core/tee-pager_v2.bin > $@ || echo "Error: Failed to create $@"


# Build UEFI firmware
$(FIRMWARE_FILE): | setup-edk2 apply-patches patch-libfdt-includes $(KEY_FILES) build-tfa
	@echo "Building UEFI firmware for RPi$(MODEL)..."
	export WORKSPACE=$(WORKSPACE) && \
	export PACKAGES_PATH="$(PACKAGES_PATH)" && \
	export GCC5_AARCH64_PREFIX="$(GCC5_AARCH64_PREFIX)" && \
	. edk2/edksetup.sh && \
	build -a $(ARCH) -t $(COMPILER) -b $(BUILD_TYPE) \
		-p platforms/Platform/RaspberryPi/RPi$(MODEL)/RPi$(MODEL).dsc \
		-D TFA_BUILD_ARTIFACTS=$(WORKSPACE)/$(TFA_ARTIFACTS_DIR) \
		--pcd gEfiMdeModulePkgTokenSpaceGuid.PcdFirmwareVersionString=L"$(VERSION)" \
		--pcd gRaspberryPiTokenSpaceGuid.PcdRamMoreThan3GB=1 \
		--pcd gRaspberryPiTokenSpaceGuid.PcdRamLimitTo3GB=0 \
		--pcd gEfiMdeModulePkgTokenSpaceGuid.PcdBootDiscoveryPolicy=2 \
		--pcd gRaspberryPiTokenSpaceGuid.PcdSystemTableMode=1 \
		--pcd gRaspberryPiTokenSpaceGuid.PcdXhciPci=0 \
		--pcd gRaspberryPiTokenSpaceGuid.PcdXhciReload=1 \
		$(BUILD_FLAGS) $(DEFAULT_KEYS) $(TLS_DISABLE_FLAGS)

# Create keys directory
$(KEYS_DIR):
	mkdir -p $(KEYS_DIR)

# Set up Secure Boot default keys
$(KEYS_DIR)/pk.cer: | $(KEYS_DIR)
	@echo "Generating Platform Key..."
	openssl req -new -x509 -newkey rsa:2048 -subj "/CN=Raspberry Pi Platform Key/" \
		-keyout /dev/null -outform DER -out $@ -days 7300 -nodes -sha256

$(KEYS_DIR)/ms_kek1.cer: | $(KEYS_DIR)
	@echo "Downloading Microsoft KEK 1..."
	curl -L https://go.microsoft.com/fwlink/?LinkId=321185 -o $@

$(KEYS_DIR)/ms_kek2.cer: | $(KEYS_DIR)
	@echo "Downloading Microsoft KEK 2..."
	curl -L https://go.microsoft.com/fwlink/?linkid=2239775 -o $@

$(KEYS_DIR)/ms_db1.cer: | $(KEYS_DIR)
	@echo "Downloading Microsoft DB 1..."
	curl -L https://go.microsoft.com/fwlink/?linkid=321192 -o $@

$(KEYS_DIR)/ms_db2.cer: | $(KEYS_DIR)
	@echo "Downloading Microsoft DB 2..."
	curl -L https://go.microsoft.com/fwlink/?linkid=321194 -o $@

$(KEYS_DIR)/ms_db3.cer: | $(KEYS_DIR)
	@echo "Downloading Microsoft DB 3..."
	curl -L https://go.microsoft.com/fwlink/?linkid=2239776 -o $@

$(KEYS_DIR)/ms_db4.cer: | $(KEYS_DIR)
	@echo "Downloading Microsoft DB 4..."
	curl -L https://go.microsoft.com/fwlink/?linkid=2239872 -o $@

$(KEYS_DIR)/arm64_dbx.bin: | $(KEYS_DIR)
	@echo "Downloading ARM64 DBX..."
	curl -L https://uefi.org/sites/default/files/resources/dbxupdate_arm64.bin -o $@

# Set up all keys
.PHONY: setup-keys
setup-keys: $(KEY_FILES)

.PHONY: build-firmware
build-firmware: $(FIRMWARE_FILE)

$(BRCM_DIR):
	mkdir -p $@

$(BRCM_DEB_FILE): $(BRCM_DIR)
	@echo "Downloading Broadcom firmware..."
	curl -L $(BRCM_FIRMWARE_URL) -o $@

$(BRCM_ARCHIVE): $(BRCM_DEB_FILE)
	@echo "Extracting Broadcom firmware archive..."
	cd $(BRCM_DIR) && \
	ar -x $(notdir $<) data.tar.xz && \
	rm $(notdir $<)

$(BRCM_FILES): $(BRCM_ARCHIVE)
	@echo "Extracting Broadcom firmware files..."
	cd $(dir $@) && \
	tar --strip-components 3 -zxvf $(notdir $<) lib/firmware

.PHONY: clean-brcm
clean-brcm:
	@echo "Cleaning Broadcom firmware..."
	rm $(BRCM_ARCHIVE)

.PHONY: setup-brcm
setup-brcm: $(BRCM_ARCHIVE)
	@echo "Extracting Broadcom firmware files..."
	cd $(BRCM_DIR) && \
	tar --strip-components 3 -xvf $(notdir $<) lib/firmware
	rm $(BRCM_ARCHIVE)

# Download Raspberry Pi support files
$(RPI_FILES): | $(ARCHIVE_DIR)
	@echo "Downloading $(notdir $@)..."
	curl -o $@ -L $(RPI_FIRMWARE_URL)/$(notdir $@)

# Create overlays directory
$(OVERLAYS_DIR):
	mkdir -p $@

$(OVERLAY_FILES): $(OVERLAYS_DIR)
	@echo "Downloading $(notdir $@)..."
	curl -L $(RPI_FIRMWARE_URL)/overlays/$(notdir $@) -o $@

# Download all Raspberry Pi support files
.PHONY: download-rpi-files
download-rpi-files: $(RPI_FILES) $(OVERLAY_FILES)

$(ARCHIVE_DIR):
	mkdir -p $(ARCHIVE_DIR)

$(ARCHIVE_DIR)/config.txt:
	cp config.txt $(ARCHIVE_DIR)/config.txt

$(ARCHIVE_DIR)/Readme.md:
	cp Readme.md $(ARCHIVE_DIR)/Readme.md

# Copy firmware to root directory with platform-specific naming
$(ARCHIVE_DIR)/RPI_EFI.fd: $(FIRMWARE_FILE) | $(ARCHIVE_DIR)
	@echo "Copying firmware to archive directory..."
	cp $(FIRMWARE_FILE) $(ARCHIVE_DIR)/RPI$(MODEL)_EFI.fd
	@# Also create generic RPI_EFI.fd for backwards compatibility
	cp $(FIRMWARE_FILE) $(ARCHIVE_DIR)/RPI_EFI.fd

$(BUILD_DIR)/$(IMAGE_FILE): $(BUILD_DIR)/$(ARCHIVE_FILE)
	@echo "Creating disk image from firmware archive..."
	@echo "Converting $(BUILD_DIR)/$(ARCHIVE_FILE) to $(BUILD_DIR)/$(IMAGE_FILE)..."
	if [ -f $(BUILD_DIR)/$(DMG_FILE) ]; then rm -f $(BUILD_DIR)/$(DMG_FILE); fi
	hdiutil create -volname RPI_BOOT -fs MS-DOS -srcfolder $(ARCHIVE_DIR) $(BUILD_DIR)/$(DMG_FILE)
	if [ -f $(BUILD_DIR)/$(IMAGE_FILE).dmg ]; then rm -f $(BUILD_DIR)/$(IMAGE_FILE).dmg; fi
	hdiutil convert $(BUILD_DIR)/$(DMG_FILE) -format UDRW -o $(BUILD_DIR)/$(IMAGE_FILE).dmg
	mv $(BUILD_DIR)/$(IMAGE_FILE).dmg $(BUILD_DIR)/$(IMAGE_FILE)
	@echo "Creating final image file..."
	@echo "Using hdiutil to create image file..."

.PHONY: flash-ssd
flash-ssd: $(BUILD_DIR)/$(ARCHIVE_FILE)
	@echo "Flashing image to device..."
	@echo "Use the following command to flash the image:"
	@echo "Eject the SD card before flashing!"
	diskutil eraseDisk FAT32 BOOT MBRFormat "$(shell diskutil list external physical | grep -E '^/' | cut -d' ' -f1 | head -n1)"
	cp -rf $(ARCHIVE_DIR)/* /Volumes/BOOT/

.PHONY: unmount-disk
unmount-disk: flash-ssd
	@echo "Unmounting disk..."
	diskutil unmountDisk "$(shell diskutil list external physical | grep -E '^/' | cut -d' ' -f1 | head -n1)"

.PHONY: copy-ssd
copy-ssd: $(FIRMWARE_FILE)
	cp $(FIRMWARE_FILE) /Volumes/BOOT/RPI_EFI.fd
	diskutil unmountDisk "$(shell diskutil list external physical | grep -E '^/' | cut -d' ' -f1 | head -n1)"

# Create UEFI firmware archive
$(BUILD_DIR)/$(ARCHIVE_FILE): $(ARCHIVE_DIR) $(ARCHIVE_DIR)/RPI_EFI.fd setup-brcm $(RPI_FILES) $(OVERLAY_FILES) $(ARCHIVE_DIR)/config.txt $(ARCHIVE_DIR)/Readme.md
	@echo "Creating UEFI firmware archive..."
	cd $(ARCHIVE_DIR) && \
	zip -r ../../$@ RPI_EFI.fd $(notdir $(RPI_FILES)) config.txt overlays Readme.md firmware efi

# Clean all platform builds
.PHONY: clean-all-platforms
clean-all-platforms:
	@echo "Cleaning all platform builds..."
	rm -rf Build/RPi3 Build/RPi4 Build/RPi5
	rm -f $(ARCHIVE_DIR)/RPI3_EFI.fd $(ARCHIVE_DIR)/RPI4_EFI.fd $(ARCHIVE_DIR)/RPI5_EFI.fd

# Display SHA-256 checksums
.PHONY: checksums
checksums: $(FIRMWARE_FILE) $(BUILD_DIR)/$(ARCHIVE_FILE)
	@echo "SHA-256 checksums:"
	sha256sum $(FIRMWARE_FILE) $(BUILD_DIR)/$(ARCHIVE_FILE)

# Build everything
.PHONY: build
build: all-platforms checksums

# Clean build artifacts
.PHONY: clean
clean:
	rm -rf edk2-platforms
	rm -rf edk2
	rm -rf Build/
	rm -rf firmware/build
	@if [ -d "$(TFA_DIR)" ]; then \
		echo "Cleaning ARM Trusted Firmware artifacts..."; \
		rm -rf $(TFA_DIR)/build; \
	fi

# Clean everything including keys
.PHONY: distclean
distclean: clean
	@echo "Cleaning all generated files..."
	rm -rf $(KEYS_DIR)

# Help target
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  all                - Build everything (default)"
	@echo "  build              - Build firmware and create archive"
	@echo "  check-deps         - Check for required dependencies"
	@echo "  apply-patches      - Apply all patches from $(PATCHES_DIR) directory"
	@echo "  build-tfa          - Build ARM Trusted Firmware for RPi$(MODEL)"
	@echo "  setup-edk2         - Build EDK2 BaseTools"
	@echo "  setup-keys         - Download and generate all security keys"
	@echo "  download-rpi-files - Download Raspberry Pi support files"
	@echo "  checksums          - Display SHA-256 checksums"
	@echo ""
	@echo "Cleanup targets:"
	@echo "  clean              - Clean build artifacts and reset platforms"
	@echo "  distclean          - Clean everything including keys"
	@echo "  help               - Show this help message"
	@echo ""
	@echo "Configuration variables:"
	@echo "  MODEL          - Raspberry Pi model (4 or 5). Default: $(MODEL)"
	@echo "  BUILD_TYPE     - Build type (RELEASE or DEBUG). Default: $(BUILD_TYPE)"
	@echo "  VERSION        - Version string (default: git describe or 'dev')"
	@echo ""
	@echo "Example: make build MODEL=5 BUILD_TYPE=DEBUG"
