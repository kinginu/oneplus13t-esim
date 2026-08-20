#!/system/bin/sh
# Fallback in case the root implementation does not apply module system.prop
# (see system.prop for what this prop does and why value 2).
RESETPROP=$(command -v resetprop || echo /data/adb/ksu/bin/resetprop)
[ -x "$RESETPROP" ] && "$RESETPROP" -n ro.vendor.oplus.esim.support 2
