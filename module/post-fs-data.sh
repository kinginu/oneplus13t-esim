#!/system/bin/sh
MODDIR=${0%/*}
MODPATH=$MODDIR
CAMERA_DIR=/odm/etc/camera


# Setting access permissions
set_perm_recursive $MODPATH 0 0 0755 0644

# Mounting /odm/lib64
mount --bind $MODDIR/odm/lib64/vendor.oplus.hardware.esim-V1-ndk.so /odm/lib64/vendor.oplus.hardware.eid-V1-ndk.so 

# Changing SELinux context
chcon -R u:object_r:vendor_file:s0 /odm/lib64
