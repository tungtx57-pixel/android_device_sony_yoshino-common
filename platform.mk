#
# Copyright (C) 2017 The LineageOS Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

PLATFORM_PATH := device/sony/yoshino-common

$(call inherit-product, $(SRC_TARGET_DIR)/product/non_ab_device.mk)

### PROPRIETARY VENDOR FILES
$(call inherit-product, vendor/sony/yoshino-common/yoshino-common-vendor.mk)

# Camera
$(call inherit-product-if-exists, vendor/sony/camera/sony-camera.mk)

PRODUCT_SOONG_NAMESPACES += \
    $(PLATFORM_PATH) \
    hardware/google/interfaces \
    hardware/google/pixel

QCOM_SOONG_NAMESPACE := $(PLATFORM_PATH)/hardware/qcom-caf

### DALVIK
$(call inherit-product, frameworks/native/build/phone-xhdpi-4096-dalvik-heap.mk)

# For android_filesystem_config.h permissions
PRODUCT_PACKAGES += \
    fs_config_dirs

# Enable dynamic partition size
PRODUCT_USE_DYNAMIC_PARTITION_SIZE := true

DEVICE_PACKAGE_OVERLAYS += \
    $(PLATFORM_PATH)/overlay

PRODUCT_ENFORCE_RRO_TARGETS += *
PRODUCT_ENFORCE_RRO_EXCLUDED_OVERLAYS += \
    $(PLATFORM_PATH)/overlay/packages/apps/FlipFlap

### Additional native libraries
PRODUCT_COPY_FILES += \
    $(PLATFORM_PATH)/config/public.libraries.txt:$(TARGET_COPY_OUT_VENDOR)/etc/public.libraries.txt \
    hardware/lineage/compat/vndk/v32/arm64/libhidlbase-v32.so:$(TARGET_COPY_OUT_SYSTEM)/lib64/libhidlbase-v32.so \
    hardware/lineage/compat/vndk/v32/arm/libhidlbase-v32.so:$(TARGET_COPY_OUT_SYSTEM)/lib/libhidlbase-v32.so

# extra build signature private vendor
-include vendor/lineage-priv/keys/keys.mk
-include vendor/evolution-priv/keys/keys.mk

### POWER
TARGET_USE_CUSTOM_POWERHINT ?= false

### RECOVERY
include $(PLATFORM_PATH)/platform/*.mk

### Kaorios Toolbox (Conditional)
ifneq ($(wildcard $(PLATFORM_PATH)/kaorios/system/priv-app/KaoriosToolbox/KaoriosToolbox.apk),)
PRODUCT_BROKEN_VERIFY_USES_LIBRARIES := true
PRODUCT_PACKAGES += KaoriosToolbox

PRODUCT_COPY_FILES += \
    $(PLATFORM_PATH)/kaorios/system/priv-app/KaoriosToolbox/lib/arm64/libandroidx.graphics.path.so:$(TARGET_COPY_OUT_SYSTEM)/priv-app/KaoriosToolbox/lib/arm64/libandroidx.graphics.path.so \
    $(PLATFORM_PATH)/kaorios/system/priv-app/KaoriosToolbox/lib/arm64/libdatastore_shared_counter.so:$(TARGET_COPY_OUT_SYSTEM)/priv-app/KaoriosToolbox/lib/arm64/libdatastore_shared_counter.so \
    $(PLATFORM_PATH)/kaorios/system/priv-app/KaoriosToolbox/lib/arm64/libkaorios_toolbox.so:$(TARGET_COPY_OUT_SYSTEM)/priv-app/KaoriosToolbox/lib/arm64/libkaorios_toolbox.so \
    $(PLATFORM_PATH)/kaorios/system/etc/permissions/com.kousei.kaorios.xml:$(TARGET_COPY_OUT_SYSTEM)/etc/permissions/com.kousei.kaorios.xml \
    $(PLATFORM_PATH)/kaorios/service.sh:$(TARGET_COPY_OUT_SYSTEM)/bin/kaorios_service.sh

endif

### ANDROID 16/17 FORWARD COMPATIBILITY
PRODUCT_MAX_PAGE_SIZE_SUPPORTED := 4096
PRODUCT_NO_BIONIC_PAGE_SIZE_MACRO := false
PRODUCT_CHECK_PREBUILT_MAX_PAGE_SIZE := false

# HIDL backward compatibility packages for Android 16/17
PRODUCT_HIDL_ENABLED := true
PRODUCT_PACKAGES += \
    hwservicemanager \
    android.hidl.base@1.0 \
    android.hidl.base@1.0.vendor \
    android.hidl.manager@1.0 \
    android.hidl.manager@1.0.vendor \
    libhidltransport \
    libhidltransport.vendor \
    libhwbinder \
    libhwbinder.vendor
