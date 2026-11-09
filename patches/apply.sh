#!/usr/bin/env bash
#
# Copyright (C) 2026 AERA Recovery Project
#
# SPDX-License-Identifier: Apache-2.0
#
# Applies Sony Yoshino (MSM8998 / Linux 4.4) compatibility updates to an
# AERA Recovery 16.0 (aera-16.0) source tree:
#   1. Legacy fscrypt v1 session keyring support + Keymaster 3.0 / Keystore2
#      readiness, null-safety guards, and Adreno 540 legacy KGSL/MDSS GPU
#      renderer support in bootable/recovery, external/lvgl, vendor/recovery,
#      system/core, system/vold, and device/qcom/twrp-common.
#   2. Soong config registration for TW_USE_FSCRYPT_POLICY and
#      AERA_UI_LEGACY_KGSL_GPU in vendor/recovery/aera_soong_config.mk and
#      vendor/twrp/config/BoardConfigSoong.mk.
#   3. Sony Yoshino device tree normalization (device/sony/*):
#      - Installs libandroidicu.so into recovery/root/system/lib64 for
#        libxml2.so -> libdrmfs.so -> qseecomd.
#      - Installs /system/bin/aera-vendor-setup.sh into recovery/root/system/bin
#        to mount oem (/mnt/vendor_gpu), modem (/firmware), persist (/persist),
#        and dsp (/dsp), populate Adreno 540 EGL/GLES/Gralloc and QMI/WLAN
#        libraries into /vendor/lib64, and stage writable Wi-Fi config/firmware.
#      - Expands firmware_directories in recovery/root/vendor/etc/ueventd.rc.
#      - Ensures twrp_*.mk inherits device/sony/yoshino-common/platform.mk and
#        declares PRODUCT_SHIPPING_API_LEVEL := 25.
#      - Fixes prepdecrypt.sh so empty ro.crypto.type defaults to file (FBE)
#        instead of exiting early before crypto.ready=1.
#      - Removes stale Android 12.1 task_profiles.json/cgroups.json and normalizes
#        recovery.fstab / twrp.flags for non-A/B fscrypt v1 ICE.
#   4. Go runtime memory cap (11 GiB GOMEMLIMIT + GOGC=40) in
#      build/soong/cmd/soong_build/main.go.
#

set -euo pipefail

PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TREE_ROOT="${1:-$(cd "${PATCH_DIR}/../../../.." && pwd)}"

apply_git_patch() {
	local rel_path="$1"
	local patch_file="${PATCH_DIR}/$2"
	local repo_dir="${TREE_ROOT}/${rel_path}"

	if [ ! -d "${repo_dir}" ] || [ ! -f "${patch_file}" ]; then
		echo "[yoshino-patches] Skipping ${rel_path} (missing directory or patch)"
		return 0
	fi

	if git -C "${repo_dir}" apply --reverse --check "${patch_file}" >/dev/null 2>&1; then
		echo "[yoshino-patches] Already applied: ${rel_path} (${2})"
		return 0
	fi

	if git -C "${repo_dir}" apply --check "${patch_file}" >/dev/null 2>&1; then
		git -C "${repo_dir}" apply "${patch_file}"
		echo "[yoshino-patches] Applied: ${rel_path} (${2})"
	elif git -C "${repo_dir}" apply --ignore-whitespace --check "${patch_file}" >/dev/null 2>&1; then
		git -C "${repo_dir}" apply --ignore-whitespace "${patch_file}"
		echo "[yoshino-patches] Applied (ignore-whitespace): ${rel_path} (${2})"
	elif git -C "${repo_dir}" apply --3way "${patch_file}" >/dev/null 2>&1; then
		echo "[yoshino-patches] Applied (3-way): ${rel_path} (${2})"
	elif patch -d "${repo_dir}" -p1 -N -r - --no-backup-if-mismatch < "${patch_file}" >/dev/null 2>&1; then
		echo "[yoshino-patches] Applied (patch fallback): ${rel_path} (${2})"
	else
		echo "[yoshino-patches] Warning: could not cleanly apply ${2} to ${rel_path}; continuing"
	fi
}

apply_git_patch "bootable/recovery" "bootable-recovery.patch"
apply_git_patch "external/lvgl" "lvgl.patch"
apply_git_patch "vendor/recovery" "vendor-recovery.patch"
apply_git_patch "device/qcom/twrp-common" "qcom-twrp-common.patch"
apply_git_patch "system/core" "system-core.patch"
apply_git_patch "system/vold" "system-vold.patch"

# 2. Ensure TW_USE_FSCRYPT_POLICY and AERA_UI_LEGACY_KGSL_GPU are exposed in both Soong config files
python3 - "${TREE_ROOT}" << 'PYEOF'
import os, sys

tree_root = sys.argv[1]
for rel in ("vendor/recovery/aera_soong_config.mk", "vendor/twrp/config/BoardConfigSoong.mk"):
    path = os.path.join(tree_root, rel)
    if not os.path.isfile(path):
        continue
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    updated = content
    if "TW_USE_FSCRYPT_POLICY" not in updated:
        updated = updated.replace(
            "TW_SUPPORT_INPUT_FF_HAPTICS \\",
            "TW_SUPPORT_INPUT_FF_HAPTICS \\\n    TW_USE_FSCRYPT_POLICY \\",
        )
    if "AERA_UI_LEGACY_KGSL_GPU" not in updated and "AERA_UI_ADAPTIVE_RESOLUTION \\" in updated:
        updated = updated.replace(
            "AERA_UI_ADAPTIVE_RESOLUTION \\",
            "AERA_UI_ADAPTIVE_RESOLUTION \\\n    AERA_UI_LEGACY_KGSL_GPU \\",
        )
    if updated != content:
        with open(path, "w", encoding="utf-8") as f:
            f.write(updated)
        print(f"[yoshino-patches] Updated {rel}")
PYEOF

# 3. Normalize Sony Yoshino device trees (device/sony/*) for Android 16 / AERA 16.0
python3 - "${TREE_ROOT}" "${PATCH_DIR}" << 'PYEOF'
import glob, os, shutil, stat, sys

tree_root = sys.argv[1]
patch_dir = sys.argv[2]
yoshino_dir = os.path.dirname(patch_dir)
icu_src = os.path.join(yoshino_dir, "recovery", "lib64", "libandroidicu.so")
sony_root = os.path.join(tree_root, "device", "sony")

VENDOR_SETUP_SH = """#!/system/bin/sh
#
# Mounts Sony Yoshino (MSM8998) firmware/vendor partitions and stages
# Adreno 540 EGL/GLES/Gralloc libraries + writable Qualcomm/Sony WLAN stack.
#

umask 022

if [ ! -e /dev/block/bootdevice ] && [ -e /dev/block/platform/soc/1da4000.ufshc ]; then
    ln -sf /dev/block/platform/soc/1da4000.ufshc /dev/block/bootdevice
fi

for f in /sys/bus/msm_subsys/devices/subsys*/restart_level; do
    [ -w "$f" ] && echo RELATED > "$f" 2>/dev/null || true
done

chmod 0666 /sys/power/wake_lock /sys/power/wake_unlock 2>/dev/null || true

mkdir -p /firmware /vendor/firmware_mnt /persist /mnt/vendor/persist /dsp /mnt/vendor_gpu /vendor/bin

if ! grep -q " /firmware " /proc/mounts 2>/dev/null; then
    mount -t vfat -o ro,shortname=lower,uid=1000,gid=1000,dmask=227,fmask=337 /dev/block/bootdevice/by-name/modem /firmware 2>/dev/null || \\
    mount -t vfat -o ro /dev/block/bootdevice/by-name/modem /firmware 2>/dev/null || true
fi
ln -sfn /firmware/image /vendor/firmware_mnt/image

if ! grep -q " /persist " /proc/mounts 2>/dev/null; then
    mount -t ext4 -o noatime,nosuid,nodev /dev/block/bootdevice/by-name/persist /persist 2>/dev/null || \\
    mount -t ext4 -o ro /dev/block/bootdevice/by-name/persist /persist 2>/dev/null || true
fi
for d in data iar_db hlos_rfs rfs wlan; do
    if [ -e "/persist/$d" ] && [ ! -e "/mnt/vendor/persist/$d" ]; then
        ln -sfn "/persist/$d" "/mnt/vendor/persist/$d"
    fi
done

if ! grep -q " /dsp " /proc/mounts 2>/dev/null; then
    mount -t ext4 -o ro,nosuid,nodev /dev/block/bootdevice/by-name/dsp /dsp 2>/dev/null || true
fi

if ! grep -q " /mnt/vendor_gpu " /proc/mounts 2>/dev/null; then
    mount -t ext4 -o ro,barrier=1 /dev/block/bootdevice/by-name/oem /mnt/vendor_gpu 2>/dev/null || \\
    mount -t erofs -o ro /dev/block/bootdevice/by-name/oem /mnt/vendor_gpu 2>/dev/null || \\
    mount -t squashfs -o ro /dev/block/bootdevice/by-name/oem /mnt/vendor_gpu 2>/dev/null || \\
    mount -o ro /dev/block/bootdevice/by-name/oem /mnt/vendor_gpu 2>/dev/null || true
fi

# Stage Qualcomm/Sony modem and WLAN daemons into /vendor/bin in RAM without
# squashfs security.capability xattrs that conflict with Linux 4.4 PR_CAP_AMBIENT.
for b in irsc_util rmt_storage pd-mapper pm-service pm-proxy qrtr-ns tftp_server cnss-daemon tad ta_qmi_service sct_service mlog_qmi_service; do
    if [ -f "/mnt/vendor_gpu/bin/$b" ]; then
        cp -f "/mnt/vendor_gpu/bin/$b" "/vendor/bin/$b"
        chmod 0755 "/vendor/bin/$b"
    fi
done

mkdir -p /vendor/lib64/hw /vendor/lib64/egl
if [ -f /system/lib64/android.hardware.keymaster@3.0-impl.so ] && [ ! -e /vendor/lib64/hw/android.hardware.keymaster@3.0-impl.so ]; then
    ln -sfn /system/lib64/android.hardware.keymaster@3.0-impl.so /vendor/lib64/hw/android.hardware.keymaster@3.0-impl.so
fi

# libhardware rejects HAL symlinks resolving outside /vendor/lib64/hw; copy gralloc into RAM.
if [ -f /mnt/vendor_gpu/lib64/hw/gralloc.msm8998.so ]; then
    cp -f /mnt/vendor_gpu/lib64/hw/gralloc.msm8998.so /vendor/lib64/hw/gralloc.msm8998.so
    chmod 0644 /vendor/lib64/hw/gralloc.msm8998.so
fi

for f in /mnt/vendor_gpu/lib64/egl/*.so; do
    [ -e "$f" ] || continue
    ln -sfn "$f" "/vendor/lib64/egl/$(basename "$f")"
done

# Expose Qualcomm GPU, Gralloc, QMI, and WLAN libraries from /mnt/vendor_gpu/lib64
# without overriding recovery's own Binder, Keymaster, or base runtime libraries.
for f in /mnt/vendor_gpu/lib64/*.so; do
    [ -e "$f" ] || continue
    b="$(basename "$f")"
    if [ ! -e "/vendor/lib64/$b" ] && [ ! -e "/system/lib64/$b" ]; then
        ln -sfn "$f" "/vendor/lib64/$b"
    fi
done

mkdir -p /vendor/etc/wifi /vendor/firmware/wlan/qca_cld
for cfg in qmi_fw.conf sec_config; do
    if [ -f "/mnt/vendor_gpu/etc/$cfg" ] && [ ! -e "/vendor/etc/$cfg" ]; then
        ln -sfn "/mnt/vendor_gpu/etc/$cfg" "/vendor/etc/$cfg"
    fi
done

for fwdir in /mnt/vendor_gpu/firmware /mnt/vendor_gpu/etc/firmware; do
    [ -d "$fwdir" ] || continue
    for entry in "$fwdir"/*; do
        [ -e "$entry" ] || continue
        name="$(basename "$entry")"
        [ "$name" = "wlan" ] && continue
        if [ ! -e "/vendor/firmware/$name" ]; then
            ln -sfn "$entry" "/vendor/firmware/$name"
        fi
    done
done

for clddir in /mnt/vendor_gpu/firmware/wlan/qca_cld /mnt/vendor_gpu/etc/firmware/wlan/qca_cld; do
    [ -d "$clddir" ] || continue
    for entry in "$clddir"/*; do
        [ -e "$entry" ] || continue
        name="$(basename "$entry")"
        if [ "$name" = "WCNSS_qcom_cfg.ini" ] || [ "$name" = "wlan_mac.bin" ]; then
            continue
        fi
        if [ ! -e "/vendor/firmware/wlan/qca_cld/$name" ]; then
            ln -sfn "$entry" "/vendor/firmware/wlan/qca_cld/$name"
        fi
    done
done

# Copy WCNSS_qcom_cfg.ini as a writable file in RAM so Wlan::PrepareStableMacFirmware()
# can update read_mac_addr_from_mac_file=1 and write /vendor/firmware/wlan/qca_cld/wlan_mac.bin.
for ini_src in /mnt/vendor_gpu/etc/wifi/WCNSS_qcom_cfg.ini /mnt/vendor_gpu/firmware/wlan/qca_cld/WCNSS_qcom_cfg.ini /mnt/vendor_gpu/etc/firmware/wlan/qca_cld/WCNSS_qcom_cfg.ini; do
    if [ -f "$ini_src" ]; then
        rm -f /vendor/etc/wifi/WCNSS_qcom_cfg.ini
        cp -f "$ini_src" /vendor/etc/wifi/WCNSS_qcom_cfg.ini
        chmod 0644 /vendor/etc/wifi/WCNSS_qcom_cfg.ini
        break
    fi
done
ln -sfn /vendor/etc/wifi/WCNSS_qcom_cfg.ini /vendor/firmware/wlan/qca_cld/WCNSS_qcom_cfg.ini

for mac_src in /persist/wlan_mac.bin /mnt/vendor/persist/wlan_mac.bin /mnt/vendor_gpu/firmware/wlan/qca_cld/wlan_mac.bin /mnt/vendor_gpu/etc/firmware/wlan/qca_cld/wlan_mac.bin; do
    if [ -f "$mac_src" ]; then
        cp -f "$mac_src" /vendor/firmware/wlan/qca_cld/wlan_mac.bin
        chmod 0644 /vendor/firmware/wlan/qca_cld/wlan_mac.bin
        break
    fi
done

if [ ! -f /vendor/etc/wifi/wpa_supplicant.conf ]; then
    if [ -f /mnt/vendor_gpu/etc/wifi/wpa_supplicant.conf ]; then
        cp -f /mnt/vendor_gpu/etc/wifi/wpa_supplicant.conf /vendor/etc/wifi/wpa_supplicant.conf
    else
        printf 'ctrl_interface=/tmp/recovery/sockets\\nupdate_config=1\\npmf=1\\n' > /vendor/etc/wifi/wpa_supplicant.conf
    fi
fi
chmod 0644 /vendor/etc/wifi/wpa_supplicant.conf 2>/dev/null || true
chmod 0755 /vendor /vendor/bin /vendor/etc /vendor/etc/wifi /vendor/firmware /vendor/firmware/wlan /vendor/firmware/wlan/qca_cld /vendor/lib64 /vendor/lib64/egl /vendor/lib64/hw 2>/dev/null || true

# WLAN helper scripts. Android 16 init drops service sections whose inline
# `sh -c` strings contain escaped quotes, $(...) or backslash sequences, so the
# bring-up logic lives in plain scripts invoked by init.recovery.wifi.rc.
# Written with printf (no heredoc): heredocs need a writable /tmp, which is not
# available yet during `on fs`.
WLAN_ON='printf '"'"'ON\\000'"'"' > /dev/wlan 2>/dev/null || true'
printf '%s\\n' \\
    '#!/system/bin/sh' \\
    'until [ "$(getprop vendor.peripheral.modem.state)" = "ONLINE" ]; do sleep 1; done' \\
    'sleep 2' \\
    "$WLAN_ON" \\
    'until [ -e /sys/class/net/wlan0 ]; do' \\
    '    sleep 1' \\
    "    $WLAN_ON" \\
    'done' \\
    'setprop wifi.driver.ready true' > /vendor/bin/aera-wlan-driver.sh

printf '%s\\n' \\
    '#!/system/bin/sh' \\
    'mkdir -p /tmp/recovery/sockets' \\
    'chmod 0777 /tmp/recovery /tmp/recovery/sockets' \\
    'until [ -e /sys/class/net/wlan0 ]; do' \\
    "    $WLAN_ON" \\
    '    sleep 0.5' \\
    'done' \\
    'exec /system/bin/wpa_supplicant -Dnl80211 -iwlan0 -O/tmp/recovery/sockets -c/vendor/etc/wifi/wpa_supplicant.conf' > /vendor/bin/aera-wpa.sh
chmod 0755 /vendor/bin/aera-wlan-driver.sh /vendor/bin/aera-wpa.sh

exit 0
"""

if os.path.isdir(sony_root):
    for dev_name in sorted(os.listdir(sony_root)):
        if dev_name == "yoshino-common":
            continue
        dev_dir = os.path.join(sony_root, dev_name)
        if not os.path.isdir(dev_dir):
            continue

        # 3a. Copy libandroidicu.so into device recovery ramdisk
        if os.path.isfile(icu_src):
            dst_lib_dir = os.path.join(dev_dir, "recovery", "root", "system", "lib64")
            os.makedirs(dst_lib_dir, exist_ok=True)
            shutil.copy2(icu_src, os.path.join(dst_lib_dir, "libandroidicu.so"))
            print(f"[yoshino-patches] Installed libandroidicu.so into device/sony/{dev_name}")

        # 3b. Install /system/bin/aera-vendor-setup.sh into device recovery ramdisk
        dst_bin_dir = os.path.join(dev_dir, "recovery", "root", "system", "bin")
        os.makedirs(dst_bin_dir, exist_ok=True)
        setup_sh_path = os.path.join(dst_bin_dir, "aera-vendor-setup.sh")
        with open(setup_sh_path, "w", encoding="utf-8") as f:
            f.write(VENDOR_SETUP_SH)
        os.chmod(
            setup_sh_path,
            stat.S_IRWXU | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH,
        )
        print(f"[yoshino-patches] Installed aera-vendor-setup.sh into device/sony/{dev_name}")

        # 3c. Expand firmware_directories in recovery/root/vendor/etc/ueventd.rc
        ueventd_path = os.path.join(dev_dir, "recovery", "root", "vendor", "etc", "ueventd.rc")
        if os.path.isfile(ueventd_path):
            with open(ueventd_path, "r", encoding="utf-8") as f:
                ueventd = f.read()
            new_fw_line = "firmware_directories /vendor/firmware_mnt/image/ /firmware/image/ /firmware/ /vendor/firmware/ /mnt/vendor_gpu/firmware/ /mnt/vendor_gpu/etc/firmware/ /etc/firmware/"
            if new_fw_line not in ueventd and "firmware_directories /vendor/firmware_mnt/image/" in ueventd:
                ueventd = ueventd.replace(
                    "firmware_directories /vendor/firmware_mnt/image/",
                    new_fw_line,
                    1,
                )
                with open(ueventd_path, "w", encoding="utf-8") as f:
                    f.write(ueventd)
                print(f"[yoshino-patches] Updated firmware_directories in {os.path.relpath(ueventd_path, tree_root)}")

        # 3d. Ensure twrp_*.mk inherits platform.mk and sets PRODUCT_SHIPPING_API_LEVEL := 25
        for mk_path in glob.glob(os.path.join(dev_dir, "twrp_*.mk")):
            with open(mk_path, "r", encoding="utf-8") as f:
                mk = f.read()
            orig_mk = mk
            if "device/sony/yoshino-common/platform.mk" not in mk:
                mk = "$(call inherit-product-if-exists, device/sony/yoshino-common/platform.mk)\n" + mk
            if "PRODUCT_SHIPPING_API_LEVEL" not in mk:
                mk += "\nPRODUCT_SHIPPING_API_LEVEL := 25\n"
            if mk != orig_mk:
                with open(mk_path, "w", encoding="utf-8") as f:
                    f.write(mk)
                print(f"[yoshino-patches] Updated {os.path.relpath(mk_path, tree_root)}")

        # 3e. Mount /firmware and /persist in init.recovery.*.rc on fs before qseecomd/keymaster start
        for rc_path in glob.glob(os.path.join(dev_dir, "recovery", "root", "init.recovery.*.rc")):
            with open(rc_path, "r", encoding="utf-8") as f:
                rc = f.read()
            if "/vendor/firmware_mnt/image" not in rc and "symlink /dev/block/platform/soc/1da4000.ufshc /dev/block/bootdevice" in rc:
                mount_snippet = (
                    "    symlink /dev/block/platform/soc/1da4000.ufshc /dev/block/bootdevice\n"
                    "    mkdir /firmware\n"
                    "    mount vfat /dev/block/bootdevice/by-name/modem /firmware ro\n"
                    "    mkdir /vendor/firmware_mnt\n"
                    "    symlink /firmware/image /vendor/firmware_mnt/image\n"
                    "    mkdir /persist\n"
                    "    mount ext4 /dev/block/bootdevice/by-name/persist /persist\n"
                    "    mkdir /mnt/vendor/persist\n"
                    "    symlink /persist/data /mnt/vendor/persist/data\n"
                    "    symlink /persist/iar_db /mnt/vendor/persist/iar_db"
                )
                rc = rc.replace(
                    "    symlink /dev/block/platform/soc/1da4000.ufshc /dev/block/bootdevice",
                    mount_snippet,
                    1,
                )
                with open(rc_path, "w", encoding="utf-8") as f:
                    f.write(rc)
                print(f"[yoshino-patches] Added /firmware and /persist mounts to {os.path.relpath(rc_path, tree_root)}")

        # 3f. Fix prepdecrypt.sh so empty ro.crypto.type defaults to file (FBE) and always sets crypto.ready=1
        prep_path = os.path.join(dev_dir, "recovery", "root", "system", "bin", "prepdecrypt.sh")
        if os.path.isfile(prep_path):
            with open(prep_path, "r", encoding="utf-8") as f:
                prep = f.read()
            orig_prep = prep
            old_maple_check = (
                'check_encrypt()\n'
                '{\n'
                '\tif [ "$sdkver" -ge 26 ]; then\n'
                '\t\tsleep 1\n'
                '\tfi\n'
                '\tencrypt_type=$(getprop ro.crypto.type)\n'
                '\tif [ "$encrypt_type" = "file" ]; then\n'
                '\t\tlog_print 1 "File Based Encryption (FBE) is present."\n'
                '\telif [ "$encrypt_type" = "block" ]; then\n'
                '\t\tlog_print 1 "Full Device Encryption (FDE) found."\n'
                '\telse\n'
                '\t\tlog_print 0 "Unknown decryption type or type not set. Exiting script."\n'
                '\t\texit 1\n'
                '\tfi\n'
                '}'
            )
            new_maple_check = (
                'check_encrypt()\n'
                '{\n'
                '\tencrypt_type=$(getprop ro.crypto.type)\n'
                '\tif [ -z "$encrypt_type" ]; then\n'
                '\t\tsetprop ro.crypto.type file\n'
                '\t\tencrypt_type="file"\n'
                '\tfi\n'
                '\tif [ "$encrypt_type" = "file" ]; then\n'
                '\t\tlog_print 1 "File Based Encryption (FBE) is present."\n'
                '\telif [ "$encrypt_type" = "block" ]; then\n'
                '\t\tlog_print 1 "Full Device Encryption (FDE) found."\n'
                '\telse\n'
                '\t\tlog_print 1 "Defaulting to File Based Encryption (FBE)."\n'
                '\t\tsetprop ro.crypto.type file\n'
                '\tfi\n'
                '}'
            )
            if old_maple_check in prep:
                prep = prep.replace(old_maple_check, new_maple_check, 1)
            old_check = 'check_encrypt() {\n\tencrypt=$(getprop "$ENCRYPT")\n\tsleep 1\n}'
            new_check = (
                'check_encrypt() {\n'
                '\tfor _i in $(seq 1 50); do\n'
                '\t\tencrypt=$(getprop "$ENCRYPT")\n'
                '\t\t[ -n "$encrypt" ] && break\n'
                '\t\tsleep 0.1\n'
                '\tdone\n'
                '}'
            )
            if old_check in prep:
                prep = prep.replace(old_check, new_check, 1)
            if "\t\t\t\tfinish\n\t\t\tfi\n\t\tfi\n\tfi\nelse" in prep:
                prep = prep.replace(
                    "\t\t\t\tfinish\n\t\t\tfi\n\t\tfi\n\tfi\nelse",
                    "\t\t\t\tfinish\n\t\t\tfi\n\t\telse\n\t\t\tfinish\n\t\tfi\n\tfi\nelse",
                    1,
                )
            if prep != orig_prep:
                with open(prep_path, "w", encoding="utf-8") as f:
                    f.write(prep)
                print(f"[yoshino-patches] Updated {os.path.relpath(prep_path, tree_root)}")

        # 3g. Remove stale Android 12.1 task_profiles.json / cgroups.json so Android 16's copy is used
        for stale_rel in (
            "recovery/root/system/etc/cgroups.json",
            "recovery/root/system/etc/task_profiles.json",
            "recovery/root/vendor/etc/cgroups.json",
            "recovery/root/vendor/etc/task_profiles.json",
        ):
            stale_path = os.path.join(dev_dir, stale_rel)
            if os.path.isfile(stale_path):
                os.remove(stale_path)
                print(f"[yoshino-patches] Removed stale {os.path.relpath(stale_path, tree_root)}")

        # 3h. Normalize recovery.fstab (fileencryption=ice:aes-256-cts:v1) and twrp.flags (remove slotselect on non-A/B)
        fstab_path = os.path.join(dev_dir, "recovery", "root", "system", "etc", "recovery.fstab")
        if os.path.isfile(fstab_path):
            with open(fstab_path, "r", encoding="utf-8") as f:
                fstab = f.read()
            if "fileencryption=ice," in fstab:
                fstab = fstab.replace("fileencryption=ice,", "fileencryption=ice:aes-256-cts:v1,")
                with open(fstab_path, "w", encoding="utf-8") as f:
                    f.write(fstab)
                print(f"[yoshino-patches] Normalized fscrypt v1 policy in {os.path.relpath(fstab_path, tree_root)}")

        flags_path = os.path.join(dev_dir, "recovery", "root", "system", "etc", "twrp.flags")
        if os.path.isfile(flags_path):
            with open(flags_path, "r", encoding="utf-8") as f:
                flags = f.read()
            if ";slotselect" in flags:
                flags = flags.replace(";slotselect", "")
                with open(flags_path, "w", encoding="utf-8") as f:
                    f.write(flags)
                print(f"[yoshino-patches] Removed non-A/B slotselect in {os.path.relpath(flags_path, tree_root)}")

        # 3i. Ensure AERA_USE_EXTREME_COMPRESSION := 1 is declared in BoardConfig.mk
        bc_path = os.path.join(dev_dir, "BoardConfig.mk")
        if os.path.isfile(bc_path):
            with open(bc_path, "r", encoding="utf-8") as f:
                bc = f.read()
            if "AERA_USE_EXTREME_COMPRESSION" not in bc:
                bc += "\n### RAMDISK EXTREME COMPRESSION\nAERA_USE_EXTREME_COMPRESSION := 1\nOF_USE_EXTREME_COMPRESSION := 1\nTW_USE_EXTREME_COMPRESSION := 1\n"
                with open(bc_path, "w", encoding="utf-8") as f:
                    f.write(bc)
                print(f"[yoshino-patches] Added AERA_USE_EXTREME_COMPRESSION := 1 to {os.path.relpath(bc_path, tree_root)}")
PYEOF

# 4. Optimize copyAeraFonts in bootable/recovery/aeraui/build/aeraui_defaults.go for 64 MiB recovery partitions / 36 MiB XBoot initrd ceiling
AERAUI_GO="${TREE_ROOT}/bootable/recovery/aeraui/build/aeraui_defaults.go"
if [ -f "${AERAUI_GO}" ]; then
	python3 - "${AERAUI_GO}" << 'PYEOF'
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

old_snippet = 'copyDir(getRecoveryAbsDir(ctx)+"aeraui/localization/fonts/assets/", fontDest)'
new_snippet = '''fontSource := getRecoveryAbsDir(ctx) + "aeraui/localization/fonts/assets/"
	if getMakeVars(ctx, "AERA_EXTRA_LANGUAGES") == "true" {
		copyDir(fontSource, fontDest)
	} else {
		for _, name := range []string{"Roboto-Regular.ttf", "Noto-OFL.txt"} {
			if err := copyFile(filepath.Join(fontSource, name),
				filepath.Join(fontDest, name)); err != nil {
				fmt.Printf("Could not copy AERA font %s: %v\\n", name, err)
				return false
			}
		}
	}'''

if old_snippet in content and "Roboto-Regular.ttf" not in content:
    content = content.replace(old_snippet, new_snippet, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("[yoshino-patches] Optimized single-language font copy in aeraui_defaults.go")
PYEOF
fi

# 5. Cap soong_build Go heap memory so env -i "$BUILDER" never swap-thrashes or OOMs on 16 GiB CI runners
SOONG_MAIN_GO="${TREE_ROOT}/build/soong/cmd/soong_build/main.go"
if [ -f "${SOONG_MAIN_GO}" ]; then
	python3 - "${SOONG_MAIN_GO}" << 'PYEOF'
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

if "debug.SetMemoryLimit" not in content:
    content = content.replace(
        '\t"path/filepath"\n',
        '\t"path/filepath"\n\t"runtime/debug"\n',
        1,
    )
    content = content.replace(
        "func main() {\n\tflag.Parse()",
        "func main() {\n\tdebug.SetGCPercent(40)\n\tdebug.SetMemoryLimit(11 * 1024 * 1024 * 1024)\n\tflag.Parse()",
        1,
    )
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("[yoshino-patches] Injected 11 GiB memory limit and GOGC=40 into soong_build/main.go")
PYEOF
fi

# 6. Browser/Telegram jail: the Yoshino 4.4 kernel has no UTS namespace
#    (CONFIG_UTS_NS unset; /proc/self/ns only lists cgroup, mnt, net), so
#    unshare(CLONE_NEWUTS) returns EINVAL and every jailed app dies at launch.
#    Request the UTS namespace and private hostname only when the kernel has it;
#    chroot, mount namespace, UID drop, rlimits and seccomp stay in force.
JAIL_MAIN="${TREE_ROOT}/bootable/recovery/aeraui/features/browser/jail_main.cpp"
if [ -f "${JAIL_MAIN}" ]; then
	python3 - "${JAIL_MAIN}" << 'PYEOF'
import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

marker = "const bool has_uts_ns"
if marker not in content:
    pattern = re.compile(
        r"(?P<indent>[ \t]*)minijail_namespace_uts\(jail\);\n"
        r"(?P<comment>(?:[ \t]*//[^\n]*\n)*)"
        r"(?P<call>[ \t]*Check\(minijail_namespace_set_hostname\(jail,.*?\"private hostname\"\);\n)",
        re.S,
    )
    match = pattern.search(content)
    if not match:
        sys.exit("[yoshino-patches] jail_main.cpp: UTS namespace block not found")
    indent = match.group("indent")
    call = "".join("  " + line if line.strip() else line
                   for line in match.group("call").splitlines(True))
    replacement = (
        f"{indent}// Linux 4.4 vendor kernels (e.g. Sony Yoshino) may lack CONFIG_UTS_NS.\n"
        f"{indent}const bool has_uts_ns = access(\"/proc/self/ns/uts\", F_OK) == 0;\n"
        f"{indent}if (has_uts_ns) minijail_namespace_uts(jail);\n"
        f"{match.group('comment')}"
        f"{indent}if (has_uts_ns) {{\n"
        f"{call}"
        f"{indent}}}\n"
    )
    content = content[:match.start()] + replacement + content[match.end():]
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("[yoshino-patches] Made browser jail UTS namespace optional for Linux 4.4")
PYEOF
fi
