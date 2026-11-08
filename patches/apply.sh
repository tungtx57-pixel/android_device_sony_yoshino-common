#!/usr/bin/env bash
#
# Copyright (C) 2026 AERA Recovery Project
#
# SPDX-License-Identifier: Apache-2.0
#
# Applies Sony Yoshino (MSM8998 / Linux 4.4) compatibility updates to an
# AERA Recovery 16.0 (aera-16.0) source tree:
#   1. Legacy fscrypt v1 session keyring support + Keymaster 3.0 / Keystore2
#      readiness and null-safety guards in bootable/recovery, system/core,
#      system/vold, and device/qcom/twrp-common.
#   2. Soong config registration for TW_USE_FSCRYPT_POLICY and
#      AERA_UI_LEGACY_KGSL_GPU in vendor/recovery/aera_soong_config.mk and
#      vendor/twrp/config/BoardConfigSoong.mk.
#   3. Sony Yoshino device tree normalization (device/sony/*):
#      - Installs libandroidicu.so into recovery/root/system/lib64 for
#        libxml2.so -> libdrmfs.so -> qseecomd.
#      - Ensures twrp_*.mk inherits device/sony/yoshino-common/platform.mk and
#        declares PRODUCT_SHIPPING_API_LEVEL := 25.
#      - Mounts /firmware (/vendor/firmware_mnt/image) and /persist
#        (/mnt/vendor/persist/data) in init.recovery.*.rc `on fs` before
#        qseecomd and keymaster-3-0-qti start.
#      - Fixes prepdecrypt.sh to poll ro.crypto.type without 1s stall and always
#        call finish (crypto.ready=1).
#      - Removes stale Android 12.1 task_profiles.json/cgroups.json and normalizes
#        recovery.fstab / twrp.flags for non-A/B fscrypt v1 ICE.
#   4. Single-language font pack optimization in
#      bootable/recovery/aeraui/build/aeraui_defaults.go.
#   5. Go runtime memory cap (11 GiB GOMEMLIMIT + GOGC=40) in
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
	elif git -C "${repo_dir}" apply --3way "${patch_file}" >/dev/null 2>&1; then
		echo "[yoshino-patches] Applied (3-way): ${rel_path} (${2})"
	else
		echo "[yoshino-patches] Warning: could not cleanly apply ${2} to ${rel_path}; continuing"
	fi
}

apply_git_patch "bootable/recovery" "bootable-recovery.patch"
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
import glob, os, shutil, sys

tree_root = sys.argv[1]
patch_dir = sys.argv[2]
yoshino_dir = os.path.dirname(patch_dir)
icu_src = os.path.join(yoshino_dir, "recovery", "lib64", "libandroidicu.so")
sony_root = os.path.join(tree_root, "device", "sony")

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

        # 3b. Ensure twrp_*.mk inherits platform.mk and sets PRODUCT_SHIPPING_API_LEVEL := 25
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

        # 3c. Mount /firmware and /persist in init.recovery.*.rc on fs before qseecomd/keymaster start
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

        # 3d. Fix prepdecrypt.sh to poll ro.crypto.type quickly and always finish with crypto.ready=1
        prep_path = os.path.join(dev_dir, "recovery", "root", "system", "bin", "prepdecrypt.sh")
        if os.path.isfile(prep_path):
            with open(prep_path, "r", encoding="utf-8") as f:
                prep = f.read()
            orig_prep = prep
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
            if "finish\n\tfi\nelse\n\tfinish\nfi" not in prep and "\t\tfinish\n\tfi\nfi" in prep:
                prep = prep.replace("\t\tfinish\n\tfi\nfi", "\t\tfinish\n\telse\n\t\tfinish\n\tfi\nelse\n\tfinish\nfi", 1)
            if prep != orig_prep:
                with open(prep_path, "w", encoding="utf-8") as f:
                    f.write(prep)
                print(f"[yoshino-patches] Updated {os.path.relpath(prep_path, tree_root)}")

        # 3e. Remove stale Android 12.1 task_profiles.json / cgroups.json so Android 16's copy is used
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

        # 3f. Normalize recovery.fstab (fileencryption=ice:aes-256-cts:v1) and twrp.flags (remove slotselect on non-A/B)
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
PYEOF

# 4. Optimize copyAeraFonts in bootable/recovery/aeraui/build/aeraui_defaults.go for 64 MiB recovery partitions
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
