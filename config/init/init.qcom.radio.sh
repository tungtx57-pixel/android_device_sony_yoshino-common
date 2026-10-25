#! /vendor/bin/sh

# Copyright (c) 2009-2016, The Linux Foundation. All rights reserved.
# Copyright (C) 2018 Sony Mobile Communications Inc#
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of The Linux Foundation nor
#       the names of its contributors may be used to endorse or promote
#       products derived from this software without specific prior written
#       permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NON-INFRINGEMENT ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
# OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
# OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# NOTE: This file has been modified by Sony Mobile Communications Inc.
# Modifications are licensed under the Sony Mobile Communications Inc's
# End User License Agreement ("EULA"). Any use of the modifications is subject
# to the terms of the EULA

#
# Make modem config folder and copy firmware config to that folder for RIL
#
mkdir -p /data/vendor/modem_config
if [ -f /data/vendor/modem_config/ver_info.txt ]; then
    prev_version_info=`cat /data/vendor/modem_config/ver_info.txt`
else
    prev_version_info=""
fi

cur_version_info=`cat /vendor/firmware_mnt/verinfo/ver_info.txt`
if [ ! -f /vendor/firmware_mnt/verinfo/ver_info.txt -o "$prev_version_info" != "$cur_version_info" ]; then
    # add W for group recursively before delete
    chmod g+w -R /data/vendor/modem_config/*
    rm -rf /data/vendor/modem_config/*
    # preserve the read only mode for all subdir and files
    cp --preserve=m -d /vendor/firmware_mnt/verinfo/ver_info.txt /data/vendor/modem_config/
    # the group must be root, otherwise this script could not add "W" for group recursively
    chown -hR radio.root /data/vendor/modem_config/*
fi
chmod g-w /data/vendor/modem_config
setprop ro.vendor.ril.mbn_copy_completed 1

# Fallback: ensure FSG partition has valid signed modem image
FSG=/dev/block/bootdevice/by-name/fsg
MODEMST1=/dev/block/bootdevice/by-name/modemst1
MODEMST2=/dev/block/bootdevice/by-name/modemst2
DEFAULT_MBN=/system/etc/customization/modem/default
RESET_MBN=/system/etc/customization/modem/reset_modemst1

if [ -f "$DEFAULT_MBN" ] && [ -b "$FSG" ]; then
    MAGIC=$(dd if=$FSG bs=1 skip=40 count=6 2>/dev/null)
    if [ "$MAGIC" != "IMGEFS" ]; then
        dd if=$DEFAULT_MBN of=$FSG bs=4096 2>/dev/null
        [ -f "$RESET_MBN" ] && dd if=$RESET_MBN of=$MODEMST1 bs=1024 2>/dev/null
        [ -f "$RESET_MBN" ] && dd if=$RESET_MBN of=$MODEMST2 bs=1024 2>/dev/null
    fi
fi
