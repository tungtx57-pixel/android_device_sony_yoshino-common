LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)

LOCAL_MODULE                  := libdrmutils
LOCAL_VENDOR_MODULE           := true
LOCAL_MODULE_TAGS             := optional
LOCAL_C_INCLUDES              := external/libdrm
LOCAL_HEADER_LIBRARIES        := generated_kernel_headers display_headers
LOCAL_SHARED_LIBRARIES        := libdrm libdl
LOCAL_CFLAGS                  := -DLOG_TAG=\"DRMUTILS\" -Wall -std=c++11 -Werror -fno-operator-names
LOCAL_CLANG                   := true
LOCAL_SRC_FILES               := drm_master.cpp drm_res_mgr.cpp drm_lib_loader.cpp

include $(BUILD_SHARED_LIBRARY)
