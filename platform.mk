#
# Copyright (C) 2017 The Android Open Source Project
# Copyright (C) 2026 AERA Recovery Project
#
# SPDX-License-Identifier: Apache-2.0
#

LOCAL_PATH := device/sony/yoshino-common
PLATFORM_PATH := device/sony/yoshino-common

# Dynamic Partitions
PRODUCT_USE_DYNAMIC_PARTITIONS := false

# Keep 4 KiB-aligned vendor recovery blobs buildable with the legacy 4.4 kernel on Android 16
PRODUCT_CHECK_PREBUILT_MAX_PAGE_SIZE := false

# Inherit from hardware-specific part of the product configuration
$(call inherit-product-if-exists, $(PLATFORM_PATH)/vendor_blobs.mk)

# QCOM FBE Decryption and AERA packages
PRODUCT_PACKAGES += \
    aera-browser-jail \
    qcom_decrypt \
    qcom_decrypt_fbe

# Processgroup task profiles required by Android 16 recovery init
PRODUCT_COPY_FILES += \
    system/core/libprocessgroup/profiles/task_profiles.json:$(TARGET_COPY_OUT_RECOVERY)/root/system/etc/task_profiles.json

# Adreno 540 EGL and MSM8998 Gralloc hardware properties
PRODUCT_VENDOR_PROPERTIES += \
    ro.hardware.egl=adreno \
    ro.hardware.gralloc=msm8998
