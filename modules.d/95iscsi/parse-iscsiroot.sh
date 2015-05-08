#!/bin/sh
#
# Preferred format:
#	root=iscsi:[<servername>]:[<protocol>]:[<port>]:[<LUN>]:<targetname>
#	[root=*] netroot=iscsi:[<servername>]:[<protocol>]:[<port>]:[<LUN>]:<targetname>
#
#       or netroot=iscsi:[<servername>]:[<protocol>]:[<port>]:[<iscsi_iface_name>]:[<netdev_name>]:[<LUN>]:<targetname>
#
#
# Legacy formats:
#	[net]root=[iscsi] iscsiroot=[<servername>]:[<protocol>]:[<port>]:[<LUN>]:<targetname>
# 	[net]root=[iscsi] iscsi_firmware
#
# root= takes precedence over netroot= if root=iscsi[...]
#

# Don't continue if root is ok
[ -n "$rootok" ] && return

# This script is sourced, so root should be set. But let's be paranoid
[ -z "$root" ] && root=$(getarg root=)
[ -z "$netroot" ] && netroot=$(getarg netroot=)
[ -z "$iscsiroot" ] && iscsiroot=$(getarg iscsiroot=)
[ -z "$iscsi_firmware" ] && getarg iscsi_firmware && iscsi_firmware="1"

[ -n "$iscsiroot" ] && [ -n "$iscsi_firmware" ] && die "Mixing iscsiroot and iscsi_firmware is dangerous"

# Root takes precedence over netroot
if [ "${root%%:*}" = "iscsi" ] ; then
    if [ -n "$netroot" ] ; then
	echo "Warning: root takes precedence over netroot. Ignoring netroot"

    fi
    netroot=$root
fi

# If it's not empty or iscsi we don't continue
[ -z "$netroot" ] || [ "${netroot%%:*}" = "iscsi" ] || return

if [ -n "$iscsiroot" ] ; then
    [ -z "$netroot" ]  && netroot=$root

    # @deprecated
    echo "Warning: Argument isciroot is deprecated and might be removed in a future"
    echo "release. See http://apps.sourceforge.net/trac/dracut/wiki/commandline for"
    echo "more information."

    # Accept iscsiroot argument?
    [ -z "$netroot" ] || [ "$netroot" = "iscsi" ] || \
	die "Argument iscsiroot only accepted for empty root= or [net]root=iscsi"

    # Override root with iscsiroot content?
    [ -z "$netroot" ] || [ "$netroot" = "iscsi" ] && netroot=iscsi:$iscsiroot
fi

initqueue --onetime modprobe --all -q -b qla4xxx cxgb3i cxgb4i bnx2i be2iscsi crc32c

# iscsi_firmware does not need argument checking
if [ -n "$iscsi_firmware" ] ; then
    netroot=${netroot:-iscsi}
    modprobe -q -b iscsi_ibft
    modprobe -q -b iscsi_boot_sysfs 2>/dev/null
    echo "[ -f '/tmp/iscsistarted-firmware' ]" > /initqueue-finished/iscsi_firmware_started.sh
fi

# If it's not iscsi we don't continue
[ "${netroot%%:*}" = "iscsi" ] || return

if [ -z "$iscsi_firmware" ] ; then
    parse_iscsi_root "$netroot" || return
fi

# ISCSI actually supported?
if ! [ -e /sys/module/iscsi_tcp ]; then
    modprobe -q -b iscsi_tcp || die "iscsiroot requested but kernel/initrd does not support iscsi"
fi

if [ -n "$iscsi_firmware" ] || \
    ( [ -n "$netroot" ] && [ "$root" != "/dev/root" ] && [ "$root" != "dhcp" ] && ! getarg "ip=" )
    then
    initqueue --onetime --settled /sbin/iscsiroot dummy "$netroot" "$NEWROOT"
else
    # also call iscsiroot for misconfigured "ip=" or link down or MAC addr change
    # or replaced NIC
    # in the timeout queue
    for nroot in $(getargs netroot); do
        [ "${nroot%%:*}" = "iscsi" ] || continue
        initqueue --onetime --timeout /sbin/iscsiroot dummy "$nroot" "$NEWROOT"
    done
fi

netroot_enc=$(str_replace "$netroot" '/' '\2f')
echo "[ -f '/tmp/iscsistarted-$netroot_enc' ]" > initqueue-finished/iscsi_started.sh

# Done, all good!
rootok=1

# Shut up init error check
[ -z "$root" ] && root="iscsi"

echo '[ -e /dev/root ]' > /initqueue-finished/iscsi.sh

