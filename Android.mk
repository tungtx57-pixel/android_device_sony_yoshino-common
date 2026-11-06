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
# Drop the optional rclone binary immediately before mkbootfs packs the
# recovery CPIO so the offline AERA recovery image stays within the 64 MiB
# hardware partition budget unless AERA_KEEP_RCLONE=1 is explicitly set.
ifneq ($(AERA_KEEP_RCLONE),1)
YOSHINO_RECOVERY_RAMDISK_STAMP := \
    $(PRODUCT_OUT)/obj/PACKAGING/recovery_intermediates/ramdisk_files-timestamp
$(YOSHINO_RECOVERY_RAMDISK_STAMP): yoshino_trim_recovery_ramdisk

.PHONY: yoshino_trim_recovery_ramdisk
yoshino_trim_recovery_ramdisk: $(TARGET_RECOVERY_ROOT_OUT)/system/bin/rclone
	@rm -f $(TARGET_RECOVERY_ROOT_OUT)/system/bin/rclone
endif

endif
