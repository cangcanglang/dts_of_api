#
# This script to update Rico Board system
# This script will respectively update the u-boot, device tree, zImage to
# QSPI.U_BOOT, QSPI.U-BOOT-DEVICETREE, QSPI.KERNEL, and update the filesystem
# to emmc
#
# Author: MYiR
# Email: support@myirtech.com
# Date: 2015.1.21
#

#!/bin/sh

# The path sdcard mounted
SD_MOUNT_POINT="/media/mmcblk1p1"
# The rootfs partition would be mounted on current 'rootfs' directory
EMMC_BOOT_MP="boot"
EMMC_ROOTFS_MP="rootfs"

FILE_UBOOT="u-boot.bin"
FILE_ZIMAGE="zImage"
FILE_DEVICETREE="myir_ricoboard.dtb"
FILE_FILESYSTEM="rootfs.tar.gz"
FILE_RAMDISK="ramdisk.gz"
FILE_UBOOTENV="u-boot-env.bin"

# eMMC is mmcblk0 and sdcard is mmcblk1
EMMC_DRIVE=

check_for_emmc()
{
        #
        # Check the eMMC was whether identified or not
        # if yes, the device node of eMMC is /dev/mmcblk0
        # and it would be filtered by 'grep "1:"'
        #
        EMMC_DEVICEDRIVENAME=`cat /proc/partitions | grep -v 'sda' | grep '\<sd.\>\|\<mmcblk.\>' | grep -n '' | grep "1:" | awk '{print $5}'`
        if [ -n $EMMC_DEVICEDRIVENAME ]; then
                EMMC_DRIVE="/dev/$EMMC_DEVICEDRIVENAME"
        else
                echo -e "Invalid emmc"
                exit 1
        fi
}

check_for_qspiflash()
{
        # Find the avaible qspi falsh
        PARTITION_TEST=`cat /proc/mtd | grep 'QSPI.'`
        if [ "$PARTITION_TEST" = "" ]; then
                echo -e "Not QSPI flash was found"
                exit 1
        fi
}

check_for_sdcards()
{
        # Find the avaible SD cards
        ROOTDRIVE=`mount | grep 'on / ' | awk {'print $1'}`
        PARTITION_TEST=`cat /proc/partitions | grep -v $ROOTDRIVE | grep '\<sd1.\>\|\<mmcblk1.\>' | grep -n ''`
        if [ "$PARTITION_TEST" = "" ]; then
                echo -e "Please insert a SD card to continue\n"
                while [ "$PARTITION_TEST" = "" ]; do
                        read -p "Type 'y' to re-detect the SD card or 'n' to exit the script: " REPLY
                        if [ "$REPLY" = 'n' ]; then
                                exit 1
                        fi
                        ROOTDRIVE=`mount | grep 'on / ' | awk {'print $1'}`
                        PARTITION_TEST=`cat /proc/partitions | grep -v $ROOTDRIVE | grep '\<sd.\>\|\<mmcblk1.\>' | grep -n ''`
                done
        fi
}

check_files_in_sdcard()
{
        # Check u-boot.bin
        if [ ! -f "$SD_MOUNT_POINT/$FILE_UBOOT" ]; then
                echo "Update failed, $SD_MOUNT_POINT/$FILE_UBOOT not exist"
                exit 1
        fi

        # Check zImage
        if [ ! -f "$SD_MOUNT_POINT/$FILE_ZIMAGE" ]; then
                echo "Update failed, $SD_MOUNT_POINT/$FILE_ZIMAGE not exist"
                exit 1
        fi

        # Check device tree
        if [ ! -f "$SD_MOUNT_POINT/$FILE_DEVICETREE" ]; then
                echo "Update failed, $SD_MOUNT_POINT/$FILE_DEVICETREE not exist"
                exit 1
        fi

        # Check filesystem
        if [ ! -f "$SD_MOUNT_POINT/$FILE_FILESYSTEM" ]; then
                echo "Update failed, $SD_MOUNT_POINT/$FILE_FILESYSTEM not exist"
                exit 1
        fi
}

qspi_update()
{
        echo "Updating u-boot.bin to QSPI flash..."
        flashcp "$SD_MOUNT_POINT/$FILE_UBOOT" /dev/mtd0
        echo "Initializing u-boot-env partitions..."
        dd if=/dev/zero of=/dev/mtd2 bs=1024 count=128 > /dev/null 2>&1
        dd if=/dev/zero of=/dev/mtd3 bs=1024 count=128 > /dev/null 2>&1

        if [ "$1" = "kern2qspi" ]; then
                echo "Updating devicetree to QSPI flash..."
                flashcp "$SD_MOUNT_POINT/$FILE_DEVICETREE" /dev/mtd4
                echo "updating zImage to QSPI flash..."
                flashcp "$SD_MOUNT_POINT/$FILE_ZIMAGE" /dev/mtd5
        fi
}

emmc_partition()
{
        #
        # Format the eMMC, the partition table were be deleted
        #
        umount $EMMC_DRIVE"p1" > /dev/null 2>&1
        umount $EMMC_DRIVE"p2" > /dev/null 2>&1
        umount $EMMC_DRIVE"p3" > /dev/null 2>&1

        dd if=/dev/zero of=$EMMC_DRIVE bs=1024 count=1024
        if [ $? -ne 0 ]; then
                echo "Format emmc failed"
                exit 1
        fi

        SIZE=`fdisk -l $EMMC_DRIVE | grep Disk | awk '{print $5}'`

        echo DISK SIZE - $SIZE bytes

        CYLINDERS=475 #`echo $SIZE/255/63/512 | bc`

        #
        # Repartition eMMC
        # first partition: rootfs, ext4, 680MB
        # second partition: extended, vfat, 2.9GB
        #
        sfdisk -D -H 255 -S 63 -C $CYLINDERS $EMMC_DRIVE <<EOF
,9,0x0c,*
10,190,0x83,-
200,,0x0c,-
EOF

        if [ $? -ne 0 ]; then
                echo "eMMC partition failed"
                exit 1
        fi

        umount $EMMC_DRIVE"p1" > /dev/null 2>&1
        sleep 1
        mkfs.fat -F 32 -n "boot" "$EMMC_DRIVE"p1
        if [ $? -ne 0 ]; then
                echo "Creating boot partition failed"
                exit 1
        fi

        umount $EMMC_DRIVE"p3" > /dev/null 2>&1
        sleep 1
        mkfs.fat -F 32 -n "extented" "$EMMC_DRIVE"p3
        if [ $? -ne 0 ]; then
                echo "Create extended partition failed"
                exit 1
        fi

        umount $EMMC_DRIVE"p2" >> /dev/null
        sleep 1
        mkfs.ext4 -L "rootfs" "$EMMC_DRIVE"p2
        if [ $? -ne 0 ]; then
                echo "Creating rootfs partition failed"
                exit 1
        fi

        mkdir $EMMC_BOOT_MP
        mount $EMMC_DRIVE"p1" $EMMC_BOOT_MP
        mkdir $EMMC_ROOTFS_MP
        mount -t ext4 $EMMC_DRIVE"p2" $EMMC_ROOTFS_MP
}

emmc_update()
{
        if [ "$1" != "kern2qspi" ]; then
                echo "Updating kernel and devicetree to emmc..."
                cp $SD_MOUNT_POINT/$FILE_ZIMAGE $EMMC_BOOT_MP
                cp $SD_MOUNT_POINT/$FILE_DEVICETREE $EMMC_BOOT_MP
                if [ -f $SD_MOUNT_POINT/$FILE_RAMDISK ]; then
                        cp $SD_MOUNT_POINT/$FILE_RAMDISK $EMMC_BOOT_MP
                fi
        fi
        echo "Updating filesystem to emmc..."

        tar xzf $SD_MOUNT_POINT/$FILE_FILESYSTEM -C $EMMC_ROOTFS_MP
        if [ $? -ne 0 ]; then
                echo "Update eMMC failed"
                umount $EMMC_ROOTFS_MP > /dev/null 2>&1
                exit 1
        fi
        sync
}

echo "All data on eMMC and QSPI flash now will be destroyed! Continue? [y/n]"
read ans
if ! [ $ans == 'y' ]
then
    exit
fi

check_for_qspiflash
check_files_in_sdcard
check_for_emmc
emmc_partition
if [ "$1" = "kern2qspi" ]; then
        qspi_update $1
        emmc_update $1
else
        qspi_update
        emmc_update
fi

echo
echo
echo -e '\033[0;33;1m Update system complated, The board can be booted from QSPI flash now \033[0m'
echo
