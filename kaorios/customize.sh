SKIPUNZIP=0

ui_print() {
  echo "$1"
}

FRAMEWORK_JAR="$MODPATH/system/framework/framework.jar"

ui_print " "
ui_print "  +==============================+"
ui_print "  |  ZYOMI16 Framework Patcher  |"
ui_print "  |    FujiOS x Kousei Toolbox   |"
ui_print "  +==============================+"
ui_print " KaoriosToolbox Module"
ui_print "────────────────────────────"

if [ ! -f "$FRAMEWORK_JAR" ]; then
  ui_print "❌ ERROR: framework.jar not found in the module!"
  ui_print "➡️  Please verify the module structure."
  abort
fi

FILE_SIZE=$(stat -c %s "$FRAMEWORK_JAR" 2>/dev/null)


if [ "$FILE_SIZE" -eq 0 ]; then
  ui_print "❌ ERROR: framework.jar is a 0 KB template file"
  ui_print " "
  ui_print "➡️  INSTRUCTIONS:"
  ui_print "   1. Extract the module ZIP"
  ui_print "   2. Replace the file at:"
  ui_print "      system/framework/framework.jar"
  ui_print "   3. Repack the ZIP and flash again"
  ui_print " "
  ui_print "⛔ Installation aborted"
  abort
fi

ui_print "✅ framework.jar is valid."

# Zyomi16 SDK guard: module chi flash dung Android da patch (chong bootloop lech version)
if [ -f "$MODPATH/zyomi16-release" ]; then
  REQ_REL=$(cat "$MODPATH/zyomi16-release" 2>/dev/null | tr -d ' \t\r\n')
  CUR_REL=$(getprop ro.build.version.release 2>/dev/null | tr -d ' \t\r\n')
  ui_print "📱 Module built for Android $REQ_REL | Device: Android $CUR_REL"
  if [ -n "$REQ_REL" ] && [ -n "$CUR_REL" ] && [ "$REQ_REL" != "$CUR_REL" ]; then
    ui_print " "
    ui_print "❌ SAI ANDROID VERSION!"
    ui_print "   Module nay patch tu Android $REQ_REL"
    ui_print "   May ban dang chay Android $CUR_REL"
    ui_print "   Flash lech version = BOOTLOOP chac chan."
    ui_print " "
    ui_print "⛔ Installation aborted (an toan)"
    abort
  fi
fi
# Run common tasks for installation and boot-time
if [ -d "$MODPATH/system" ]; then
    . $MODPATH/service.sh
fi

# Clean up any leftover files from previous deprecated methods
rm -f /data/data/com.google.android.gms/cache/pif.prop /data/data/com.google.android.gms/pif.prop \
    /data/data/com.google.android.gms/cache/pif.json /data/data/com.google.android.gms/pif.json
# rm -rf /data/system/dropbox/*
rm -rf /data/system/package_cache/*
