until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 1
done

#Find resetprop
resetprop=$(find /data/adb -name "resetprop" 2>/dev/null | head -n 1)

if [ -z "$resetprop" ]; then
    echo "[!] Not found resetprop"
    resetprop=resetprop
fi

PROPERTIES="
ro.boot.verifiedbootstate=green
ro.boot.veritymode=enforcing
vendor.boot.vbmeta.device_state=locked
ro.crypto.state=encrypted
ro.secureboot.lockstate=locked
ro.boot.flash.locked=1
ro.boot.vbmeta.device_state=locked
ro.boot.selinux=enforcing
sys.oem_unlock_allowed=0
ro.boot.veritymode.managed=yes
ro.debuggable=0
ro.force.debuggable=0
ro.secure=1
ro.boot.realmebootstate=green
ro.boot.warranty_bit=0
ro.vendor.boot.warranty_bit=0
ro.vendor.warranty_bit=0
ro.warranty_bit=0
ro.boot.realme.lockstate=1
vendor.boot.verifiedbootstate=green
"

echo "=== SET PROPERTIES ==="
for item in $PROPERTIES; do
    key="${item%%=*}"
    val="${item#*=}"
    if [ -x "$resetprop" ]; then "$resetprop" "$key" "$val"; else setprop "$key" "$val"; fi
done

echo "Done!"
echo ""

echo "=== GETPROP ==="
for item in $PROPERTIES; do
    key="${item%%=*}"
    current_val=$(getprop "$key")
    if [ -z "$current_val" ]; then
        echo "[-] $key : (trống)"
    else
        echo "[+] $key : $current_val"
    fi
done
