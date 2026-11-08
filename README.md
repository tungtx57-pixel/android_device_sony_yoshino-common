# Sony Xperia Yoshino Common Recovery Tree (AERA Recovery 16.0 / TWRP)

Common platform configuration (`msm8998` / Snapdragon 835) for Sony Xperia Yoshino devices:

- **Sony Xperia XZ Premium**: `maple`, `maple_dsds` (`G8141`, `G8142`, `SO-04J`)
- **Sony Xperia XZ1**: `poplar`, `poplar_dsds`, `poplar_canada`, `poplar_kddi` (`G8341`, `G8342`, `G8343`, `SO-01K`, `SOV36`, `701SO`)
- **Sony Xperia XZ1 Compact**: `lilac` (`G8441`, `SO-02K`)

---

## Architecture & AERA Recovery 16.0 (`aera-16.0`) Adaptations

1. **Android 16 (`bp2a`) Build System Compatibility ([`BoardConfigPlatform.mk`](BoardConfigPlatform.mk), [`platform.mk`](platform.mk))**:
   - Removed deprecated `PRODUCT_FULL_TREBLE_OVERRIDE` (which triggers a fatal `KATI_obsolete_var` abort on Android 16).
   - Enabled `PRODUCT_CHECK_PREBUILT_MAX_PAGE_SIZE := false` and `BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true` so 4 KiB-aligned MSM8998 vendor blobs remain buildable on Android 16.
   - Added Android 16 Soong plugin validation exemptions (`soong-libaosprecovery_defaults`, `soong-libguitwrp_defaults`, `soong-libminuitwrp_defaults`, `soong-vold_defaults`).
   - Replaced obsolete `TW_RECOVERY_ADDITIONAL_RELINK_FILES` with `AERA_RECOVERY_ADDITIONAL_RELINK_LIBRARY_FILES` / `TW_RECOVERY_ADDITIONAL_RELINK_LIBRARY_FILES` and included `android.hardware.boot-V1-ndk`, `libboot_control_client`, `android.hardware.keymaster@3.0-impl`, `libkeymaster3device`, `libpuresoftkeymasterdevice`, `libxml2`, `libicuuc`, and `android.hardware.weaver@1.0`.
   - Added `system/core/libprocessgroup/profiles/task_profiles.json` copy rule required by Android 16 recovery `init`.

2. **MSM8998 Hardware Encryption (Keymaster 3.0 + Legacy fscrypt v1 ICE)**:
   - Configured `AERA_INCLUDE_CRYPTO := true`, `AERA_INCLUDE_CRYPTO_FBE := true`, `AERA_USE_FSCRYPT_POLICY := 1`, `AERA_DEFAULT_KEYMASTER_VERSION := 3.0`, and `AERA_FORCE_KEYMASTER_VER := true`.
   - Exported `TW_USE_FSCRYPT_POLICY` to Soong `twrpVarsPlugin`.
   - Included [`patches/apply.sh`](patches/apply.sh) (`qcom-twrp-common.patch`, `system-core.patch`, `system-vold.patch`) to restore the `install_keyring` builtin in `init` and legacy session keyring fallback in `vold` for Linux 4.4 kernels lacking fscrypt v2 ioctls.

3. **64 MiB Recovery Partition Budget ([`Android.mk`](Android.mk), [`patches/apply.sh`](patches/apply.sh))**:
   - Sony Yoshino devices have a fixed 64 MiB (`67108864` bytes) `recovery` / `boot` partition.
   - [`Android.mk`](Android.mk) strips the optional `rclone` binary before `mkbootfs` packages the recovery CPIO (unless `AERA_KEEP_RCLONE=1` is set).
   - [`patches/apply.sh`](patches/apply.sh) restricts single-language builds (`AERA_EXTRA_LANGUAGES=false`) to the core `Roboto-Regular.ttf` fallback font instead of copying all CJK/Indic font assets into `/twres/fonts/`.

4. **AERA Display, Legacy MDSS `fbdev` & 16:9 UI Configuration ([`BoardConfigPlatform.mk`](BoardConfigPlatform.mk), [`vendorsetup.sh`](vendorsetup.sh), [`patches/bootable-recovery.patch`](patches/bootable-recovery.patch))**:
   - Automatically exports public `AERA_*` flags for `maple`, `poplar`, and `lilac` when sourced by `build/envsetup.sh` or `build/soong/soong_ui.bash` (`vendor/recovery/AERA_A16.sh`).
   - Fixes a fatal `SIGABRT` on Frame 1 in `res_scale_surface()` (`minuitwrp/resources.cpp`) where a stack-allocated `GGLSurface` was passed to `free()`, and adds a single-pass zero-allocation bilinear `BGRA -> RGBA` software presenter for legacy MDSS `fbdev` (`1440x2560` logical -> `1080x1920` physical at 60 fps) with native `FBIOBLANK` panel unblanking.
   - Adapts AERA UI scenes (`Menu`, `Decrypt`, `Terminal`, `Format Data`, `Operation`, `Reboot`, `About`, `Files`) and dynamic `cpufreq/policy*` boost for 16:9 MSM8998 panels.

---

## Building via GitHub Actions Workflow

Trigger [`.github/workflows/Aera.yml`](.github/workflows/Aera.yml) via **Actions -> Build AERA Recovery (Sony Yoshino) -> Run workflow**:

| Input | Default | Description |
|---|---|---|
| `DEVICE_NAME` | `maple` | Target codename (`maple`, `poplar`, `lilac`) |
| `DEVICE_TREE` | `https://github.com/tungtx57-pixel/android_device_sony_maple` | Companion device tree repository |
| `DEVICE_BRANCH` | `android-12.1` | Companion device tree branch |
| `AERA_BRANCH` | `aera-16.0` | AERA Recovery manifest branch |
| `BUILD_TARGET` | `recoveryimage` | `recoveryimage` or `bootimage` |
| `MAINTAINER` | `tungtx57-pixel` | Maintainer name embedded in AERA build |
| `ENABLE_ROOT_MANAGER` | `false` | Pack offline KernelSU/SukiSU LKM providers |

---

## Local Build Instructions

```bash
repo init -u https://github.com/AERA-Recovery/android_manifest.git -b aera-16.0 --depth=1 --git-lfs
repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags

git clone -b aera-16.0 https://github.com/tungtx57-pixel/android_device_sony_yoshino-common device/sony/yoshino-common
git clone -b android-12.1 https://github.com/tungtx57-pixel/android_device_sony_maple device/sony/maple

# Apply MSM8998 Linux 4.4 fscrypt v1, fbdev UI, and 64 MiB font budget adaptations
bash device/sony/yoshino-common/patches/apply.sh "$(pwd)"

export ALLOW_MISSING_DEPENDENCIES=true
export LC_ALL="C"
export AERA_BUILD_DEVICE="maple"
source build/envsetup.sh
lunch twrp_maple-bp2a-eng
mka adbd recoveryimage -j$(nproc --all)
```
