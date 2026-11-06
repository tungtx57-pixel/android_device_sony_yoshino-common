#!/usr/bin/env bash
#
# Copyright (C) 2026 AERA Recovery Project
#
# SPDX-License-Identifier: Apache-2.0
#
# Common AERA Recovery 16.0 environment configuration for Sony Yoshino
# (MSM8998 / Snapdragon 835): maple, poplar, lilac.
#

yoshino_setup_aera_env() {
	local target_dev="${1:-${AERA_BUILD_DEVICE:-}}"
	case "${target_dev}" in
		maple|maple_dsds|poplar|poplar_dsds|poplar_canada|poplar_kddi|lilac)
			;;
		*)
			return 0
			;;
	esac

	export LC_ALL="C"
	export ALLOW_MISSING_DEPENDENCIES=true

	# Build & Maintainer Identity
	export AERA_BUILD_DEVICE="${target_dev}"
	export AERA_MAINTAINER="${AERA_MAINTAINER:-tungtx57-pixel}"
	export AERA_MAINTAINER_PATCH_VERSION="${AERA_MAINTAINER_PATCH_VERSION:-1}"
	export AERA_BUILD_TYPE="${AERA_BUILD_TYPE:-Stable}"
	export AERA_VANILLA_BUILD=1

	# Device Variant Assertions
	case "${target_dev}" in
		maple|maple_dsds)
			export TARGET_DEVICE_ALT="maple,maple_dsds,G8141,G8142,SO-04J"
			;;
		poplar|poplar_dsds|poplar_canada|poplar_kddi)
			export TARGET_DEVICE_ALT="poplar,poplar_dsds,poplar_canada,poplar_kddi,G8341,G8342,G8343,SO-01K,SOV36,701SO"
			;;
		lilac)
			export TARGET_DEVICE_ALT="lilac,G8441,SO-02K"
			;;
	esac

	# Partition & Block Paths (Non-AB / Legacy Treble)
	export AERA_AB_DEVICE=0
	export AERA_VIRTUAL_AB_DEVICE=0
	export AERA_RECOVERY_INSTALL_PARTITION="/dev/block/bootdevice/by-name/recovery"
	export AERA_RECOVERY_SYSTEM_PARTITION="/dev/block/bootdevice/by-name/system"
	export AERA_RECOVERY_VENDOR_PARTITION="/dev/block/bootdevice/by-name/vendor"
	export AERA_RECOVERY_BOOT_PARTITION="/dev/block/bootdevice/by-name/boot"
	export AERA_NO_TREBLE_COMPATIBILITY_CHECK=1
	export AERA_SKIP_MULTIUSER_FOLDERS_BACKUP=1
	export AERA_QUICK_BACKUP_LIST="/boot;/data;"
	export AERA_ENABLE_BACKUP_ENCRYPTION=1

	# Display & Statusbar Geometry (16:9 Sony Yoshino Panels)
	export AERA_SCREEN_H=1920
	export AERA_STATUS_H=80
	export AERA_STATUS_INDENT_LEFT=48
	export AERA_STATUS_INDENT_RIGHT=48
	export AERA_HIDE_NOTCH=0
	export AERA_CLOCK_POS=1
	export AERA_ALLOW_DISABLE_NAVBAR=0
	export AERA_USE_GREEN_LED=0

	# Shell, Archive & Recovery Utilities
	export AERA_USE_BASH_SHELL=1
	export AERA_ASH_IS_BASH=1
	export AERA_USE_TAR_BINARY=1
	export AERA_USE_SED_BINARY=1
	export AERA_USE_XZ_UTILS=1
	export AERA_USE_ZSTD_BINARY=1
	export AERA_USE_GREP_BINARY=1
	export AERA_USE_BUSYBOX_BINARY=1
	export AERA_ENABLE_APP_MANAGER=1
	export AERA_DELETE_AROMAFM=1
	export AERA_ENABLE_LAB=1
	export AERA_LOOP_DEVICE_ERRORS_TO_LOG=1
	export AERA_USE_LEGACY_BATTERY_SERVICES=1

	# Keep offline root provider LKM packs disabled by default to fit 64 MiB recovery slot
	export AERA_ENABLE_ROOT_MANAGER="${AERA_ENABLE_ROOT_MANAGER:-0}"
}

yoshino_setup_aera_env "$1"
unset -f yoshino_setup_aera_env
