#!/usr/bin/env bash
#
# Copyright (C) 2026 AERA Recovery Project
#
# SPDX-License-Identifier: Apache-2.0
#
# Applies Sony Yoshino (MSM8998 / Linux 4.4) compatibility patches to an
# AERA Recovery 16.0 (aera-16.0) source tree:
#   1. Legacy fscrypt v1 session keyring support in system/core, system/vold,
#      and device/qcom/twrp-common.
#   2. Soong config registration for TW_USE_FSCRYPT_POLICY and
#      AERA_UI_LEGACY_KGSL_GPU in vendor/recovery/aera_soong_config.mk.
#   3. Single-language font pack optimization in
#      bootable/recovery/aeraui/build/aeraui_defaults.go to keep recovery.img
#      well within Sony Yoshino's 64 MiB recovery partition.
#   4. Go runtime memory cap (11 GiB GOMEMLIMIT + GOGC=40) in
#      build/soong/cmd/soong_build/main.go so soong_build (invoked via env -i)
#      never thrashes swap or triggers OOM on 16 GiB CI runners.
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

# Ensure TW_USE_FSCRYPT_POLICY and AERA_UI_LEGACY_KGSL_GPU are exposed in vendor/recovery/aera_soong_config.mk
SOONG_CFG="${TREE_ROOT}/vendor/recovery/aera_soong_config.mk"
if [ -f "${SOONG_CFG}" ]; then
	python3 - "${SOONG_CFG}" << 'PYEOF'
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

updated = content
if "TW_USE_FSCRYPT_POLICY" not in updated:
    updated = updated.replace(
        "TW_SUPPORT_INPUT_FF_HAPTICS \\",
        "TW_SUPPORT_INPUT_FF_HAPTICS \\\n    TW_USE_FSCRYPT_POLICY \\",
    )
if "AERA_UI_LEGACY_KGSL_GPU" not in updated:
    updated = updated.replace(
        "AERA_UI_ADAPTIVE_RESOLUTION \\",
        "AERA_UI_ADAPTIVE_RESOLUTION \\\n    AERA_UI_LEGACY_KGSL_GPU \\",
    )

if updated != content:
    with open(path, "w", encoding="utf-8") as f:
        f.write(updated)
    print("[yoshino-patches] Updated vendor/recovery/aera_soong_config.mk")
PYEOF
fi

# Optimize copyAeraFonts in bootable/recovery/aeraui/build/aeraui_defaults.go for 64 MiB recovery partitions
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

# Cap soong_build Go heap memory so env -i "$BUILDER" never swap-thrashes or OOMs on 16 GiB CI runners
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
