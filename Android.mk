#
# Copyright (C) 2017 The Android Open Source Project
# Copyright (C) 2026 AERA Recovery Project
#
# SPDX-License-Identifier: Apache-2.0
#

LOCAL_PATH := $(call my-dir)

ifneq ($(filter lilac maple maple_dsds poplar poplar_canada poplar_dsds poplar_kddi,$(TARGET_DEVICE)),)

include $(call all-subdir-makefiles,$(LOCAL_PATH))

# Sony Yoshino's recovery partition is a fixed 64 MiB boot image slot.
# Drop the optional rclone binary using a real file stamp (Kati forbids real
# targets depending on .PHONY) immediately before mkbootfs packs the recovery
# CPIO unless AERA_KEEP_RCLONE=1 is explicitly set.
ifneq ($(AERA_KEEP_RCLONE),1)
YOSHINO_RCLONE_OUT := $(TARGET_RECOVERY_ROOT_OUT)/system/bin/rclone
YOSHINO_RAMDISK_TRIM_STAMP := $(TARGET_RECOVERY_ROOT_OUT)/.yoshino-ramdisk-trim

$(YOSHINO_RAMDISK_TRIM_STAMP): $(YOSHINO_RCLONE_OUT)
	@echo "Yoshino: omitting rclone to stay within the 64 MiB recovery partition budget"
	@mkdir -p $(dir $@) && rm -f $(YOSHINO_RCLONE_OUT) && touch $@

$(PRODUCT_OUT)/obj/PACKAGING/recovery_intermediates/ramdisk_files-timestamp: \
    $(YOSHINO_RAMDISK_TRIM_STAMP)
endif

endif
