# Sony Xperia Yoshino Common Recovery Tree (AERA Recovery 16.0 / TWRP)

Common platform configuration (`msm8998` / Snapdragon 835) for Sony Xperia Yoshino devices:

- **Sony Xperia XZ Premium**: `maple`, `maple_dsds` (`G8141`, `G8142`, `SO-04J`)
- **Sony Xperia XZ1**: `poplar`, `poplar_dsds`, `poplar_canada`, `poplar_kddi` (`G8341`, `G8342`, `G8343`, `SO-01K`, `SOV36`, `701SO`)
- **Sony Xperia XZ1 Compact**: `lilac` (`G8441`, `SO-02K`)

---

## Architecture & AERA Recovery 16.0 (`aera-16.0`) Adaptations

1. **Android 16 (`bp2a`) Build System Compatibility ([`BoardConfigPlatform.mk`](BoardConfigPlatform.mk), [`platform.mk`](platform.mk), [`recovery/Android.mk`](recovery/Android.mk))**:
   - Removed deprecated `PRODUCT_FULL_TREBLE_OVERRIDE` (which triggers a fatal `KATI_obsolete_var` abort on Android 16).
   - Enabled `PRODUCT_CHECK_PREBUILT_MAX_PAGE_SIZE := false`, `PRODUCT_USE_DYNAMIC_PARTITIONS := false`, and `BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true` so 4 KiB-aligned MSM8998 vendor blobs remain buildable on Android 16.
   - Added Android 16 Soong plugin validation exemptions (`soong-libaosprecovery_defaults`, `soong-libguitwrp_defaults`, `soong-libminuitwrp_defaults`, `soong-vold_defaults`).
   - Installed `recovery/lib64/libandroidicu.so` (`libandroidicu_yoshino`) into `/system/lib64/libandroidicu.so` so Android 16's `/system/lib64/libxml2.so` (`NEEDED: libandroidicu.so`) -> `libdrmfs.so` -> `qseecomd` dynamically links cleanly at boot.
   - Enabled `recovery: true` on `system/core/libprocessgroup/profiles/task_profiles.json` and removed stale Android 12.1 `task_profiles.json` / `cgroups.json` from companion device trees.

2. **MSM8998 Hardware Encryption (Keymaster 3.0 + Legacy fscrypt v1 ICE)**:
   - Configured `AERA_INCLUDE_CRYPTO := true`, `AERA_INCLUDE_CRYPTO_FBE := true`, `AERA_USE_FSCRYPT_POLICY := 1`, `AERA_DEFAULT_KEYMASTER_VERSION := 3.0`, and `AERA_FORCE_KEYMASTER_VER := true`.
   - Exported `TW_USE_FSCRYPT_POLICY` to Soong `twrpVarsPlugin` in both `vendor/recovery/aera_soong_config.mk` and `vendor/twrp/config/BoardConfigSoong.mk`.
   - Included [`patches/apply.sh`](patches/apply.sh) (`bootable-recovery.patch`, `qcom-twrp-common.patch`, `system-core.patch`, `system-vold.patch`) to:
     - Restore the `install_keyring` builtin in `init` and legacy session keyring fallback in `vold` for Linux 4.4 kernels lacking fscrypt v2 ioctls.
     - Mount `/firmware` (`/vendor/firmware_mnt/image`) and `/persist` (`/mnt/vendor/persist/data`) in `init.recovery.*.rc` `on fs` before `qseecomd` and `keymaster-3-0-qti` start.
     - Wait for `crypto.ready=1` and `vendor.sys.listeners.registered=true` before `Decrypt_FBE_DE()` invokes `Decrypt_DE()`, and guard `KeyStorage.cpp`, `Keystore.cpp`, `Decrypt.cpp`, and `FsCrypt.cpp` against null pointers and empty optionals.

3. **64 MiB Recovery Slot & 36 MiB Sony XBoot Initrd Ceiling ([`Android.mk`](Android.mk), [`patches/vendor-recovery.patch`](patches/vendor-recovery.patch), [`patches/apply.sh`](patches/apply.sh))**:
   - Sony Yoshino devices have a fixed 64 MiB (`67108864` bytes) `recovery` / `boot` partition and a 36 MiB (`splash_region@9d400000`) bootloader initrd limit in Sony XBoot.
   - [`Android.mk`](Android.mk) strips the optional `rclone` binary before `mkbootfs` packages the recovery CPIO (unless `AERA_KEEP_RCLONE=1` is set).
   - [`patches/apply.sh`](patches/apply.sh) and [`patches/vendor-recovery.patch`](patches/vendor-recovery.patch) restrict single-language builds (`AERA_EXTRA_LANGUAGES=false`) to `Roboto-Regular.ttf`, omit redundant `/sbin` prebuilts (`aapt`, `bash`, `gnutar`, `gnused`, `zstd`, `zip`, `nano`), prune `/system/etc/terminfo` to essential terminal definitions, and strip unneeded ELF symbol tables (`--strip-unneeded`) while preserving `/sbin/busybox`, `/sbin/magiskboot`, `/system/bin/htop`, Adreno 540 GPU, and Wi-Fi.

4. **Adreno 540 Legacy KGSL GPU, MSM8998 Wi-Fi & 16:9 UI Configuration ([`BoardConfigPlatform.mk`](BoardConfigPlatform.mk), [`recovery/init.recovery.wifi.rc`](recovery/init.recovery.wifi.rc), [`patches/bootable-recovery.patch`](patches/bootable-recovery.patch), [`patches/lvgl.patch`](patches/lvgl.patch))**:
   - Enables `AERA_UI_LEGACY_KGSL_GPU := true` (`gralloc.msm8998.so` + Adreno 540 `libEGL_adreno.so` / `libGLESv2_adreno.so` zero-copy `EGLImage` / `glBlitFramebuffer` renderer on legacy MDSS `fbdev` with automatic software fallback) and `OF_ENABLE_WLAN := 1` (`wpa_supplicant`, `wpa_cli`, `dhcptool`, `aera-netfs`, `ttyd`, `aera-browser-jail`, and `init.recovery.wifi.rc` / `aera-vendor-setup.sh`).
   - Stages Qualcomm and Sony modem/WLAN daemons (`pm-service`, `pm-proxy`, `rmt_storage`, `pd-mapper`, `qrtr-ns`, `tftp_server`, `cnss-daemon`, `tad`, `ta_qmi_service`, `sct_service`, `mlog_qmi_service`, `irsc_util`) into `/vendor/bin` in RAM without `squashfs` `security.capability` xattrs (avoiding Linux 4.4 `PR_CAP_AMBIENT` `-EPERM`), triggers IPA v3 firmware load (`write /dev/ipa 1`), sets `subsys*/restart_level` to `RELATED`, and waits for `/sys/class/net/wlan0` in `service wpa_supplicant` before executing `/system/bin/wpa_supplicant`.
   - `aera-vendor-setup.sh` writes `/vendor/bin/aera-wlan-driver.sh` and `/vendor/bin/aera-wpa.sh` with `printf` (no heredoc, since `/tmp` is not writable during `on fs`). The `aera-wlan-driver` and `wpa_supplicant` services call these scripts because Android 16 `init` silently drops service sections whose inline `sh -c` strings contain escaped quotes, `$(...)` or backslash sequences.
   - [`patches/apply.sh`](patches/apply.sh) step 6 makes the AERA Browser / Telegram jail (`aeraui/features/browser/jail_main.cpp`) request the UTS namespace and private hostname only when `/proc/self/ns/uts` exists. The Yoshino 4.4 kernel lacks `CONFIG_UTS_NS`, so `unshare(CLONE_NEWUTS)` returned `EINVAL` and killed every jailed app. Chroot, mount namespace, UID drop, rlimits and seccomp are unchanged.
   - Fixes a fatal `SIGABRT` on Frame 1 in `res_scale_surface()` (`minuitwrp/resources.cpp`), prevents the Sony Yoshino MDSS DSI + Synaptics ClearPad `incell_panel_power_worker` <-> `cancel_work_sync()` AB-BA kernel deadlock on `FBIOBLANK` in `minuitwrp/graphics_fbdev.cpp` (`AERA_NO_SCREEN_BLANK := true`), and guards `gpt_disk_get_disk_info()` (`gpt/gpt.c:253`) against null buffers.
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
