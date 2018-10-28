#!/bin/bash

trap '{ stty sane; echo ""; errexit "Aborted"; }' SIGINT SIGTERM

BOOTBEG=2048
BOOTEND=88063
ROOTBEG=88064

MNTPATH="/tmp/usb-boot-mnt"

mntusb()
{
  if [ ! -d "${MNTPATH}/" ]; then
    mkdir "${MNTPATH}/"
    if [ $? -ne 0 ]; then
      errexit "Unable to make ROOT partition mount point"
    fi
  fi
  mount "${USB_ROOT}" "${MNTPATH}/"
  if [ $? -ne 0 ]; then
    errexit "Unable to mount ROOT partition"
  fi
  if [ ! -d "${MNTPATH}/boot/" ]; then
    mkdir -p "${MNTPATH}/boot/"
    if [ $? -ne 0 ]; then
      errexit "Unable to make BOOT partition mount point"
    fi
  fi
  mount "${USB_BOOT}" "${MNTPATH}/boot/"
  if [ $? -ne 0 ]; then
    errexit "Unable to mount BOOT partition"
  fi
}

umntusb()
{
  umount "${MNTPATH}/boot/"
  if [ $? -ne 0 ]; then
    errexit "Unable to unmount BOOT partition"
  fi
  umount "${MNTPATH}/"
  if [ $? -ne 0 ]; then
    errexit "Unable to unmount ROOT partition"
  fi
  rm -r "${MNTPATH}/"
}

errexit()
{
  echo ""
  echo "$1"
  echo ""
  umount "${MNTPATH}/boot/" &> /dev/null
  umount "${MNTPATH}/" &> /dev/null
  rm -r "${MNTPATH}/" &> /dev/null
  exit 1
}

if [ $(id -u) -ne 0 ]; then
  errexit "$0 must be run as root user"
fi

rsync --version &> /dev/null
if [ $? -ne 0 ]; then
  errexit "rsync not installed (run: apt-get install rsync)"
fi

if command -v systemctl > /dev/null && systemctl | grep -q '\-\.mount'; then
  SYSTEMD=1
elif [ -f /etc/init.d/cron ] && [ ! -h /etc/init.d/cron ]; then
  SYSTEMD=0
else
  errexit "Unrecognized init system"
fi

if [ ${SYSTEMD} -eq 1 ]; then
  ROOT_PART="$(mount | sed -n 's|^/dev/\(.*\) on / .*|\1|p')"
else
  if [ ! -h /dev/root ]; then
    errexit "/dev/root does not exist or is not a symlink"
  fi
  ROOT_PART="$(readlink /dev/root)"
fi

ROOT_TYPE=$(blkid "/dev/${ROOT_PART}" | sed -n 's|^.*TYPE="\(\S\+\)".*|\1|p')

ROOT_DEV="${ROOT_PART:0:(${#ROOT_PART} - 1)}"
if [ "${ROOT_DEV}" = "mmcblk0p" ]; then
  ROOT_DEV="${ROOT_DEV:0:(${#ROOT_DEV} - 1)}"
fi

USBDEVS=($(ls -l /dev/sd? | sed -n 's|^.*\(/dev/.*\)|\1|p'))
for i in ${!USBDEVS[@]}; do
  if [ "${USBDEVS[i]}" != "/dev/${ROOT_DEV}" ]; then
    USBDEVS[i]="${USBDEVS[i]} ${USBDEVS[i]} OFF"
  else
    unset -v USBDEVS[i]
  fi
done

if [ ${#USBDEVS[@]} -eq 0 ]; then
  errexit "No available USB mass storage devices found"
fi

USB_DEST="$(whiptail --backtitle "USB Boot" --title "USB Mass Storage Devices" --notags --radiolist \
"\nSelect the USB mass storage device to boot" 13 47 ${#USBDEVS[@]} ${USBDEVS[@]} 3>&1 1>&2 2>&3)"
if [[ $? -ne 0 || "${USB_DEST}" = "" ]]; then
  errexit "Aborted"
fi
USB_BOOT="${USB_DEST}1"
USB_ROOT="${USB_DEST}2"

whiptail --backtitle "USB Boot" --title "Replicate BOOT/ROOT Contents"  --yesno "\nReplicate BOOT/ROOT contents from /dev/${ROOT_DEV} to ${USB_DEST}?" 12 64
YESNO=$?
if [ ${YESNO} -eq 255 ]; then
  errexit "Aborted"
elif [ ${YESNO} -eq 0 ]; then
  whiptail --backtitle "USB Boot" --title "WARNING"  --yesno "\nWARNING\n\nAll existing data on USB device ${USB_DEST} will be destroyed!\n\nDo you wish to continue?" 14 64
  YESNO=$?
  if [ ${YESNO} -ne 0 ]; then
    errexit "Aborted"
  fi
  echo ""
  echo "Replicating BOOT/ROOT contents from /dev/${ROOT_DEV} to ${USB_DEST} (this will take a while)"
  fdisk "${USB_DEST}" <<EOF &> /dev/null
p
o
n
p
1
${BOOTBEG}
${BOOTEND}
t
c
p
n
p
2
${ROOTBEG}

p
w
EOF
  mkfs.vfat "${USB_BOOT}" > /dev/null
  if [ $? -ne 0 ]; then
    errexit "Unable to create BOOT filesystem"
  fi
  dosfsck "${USB_BOOT}" > /dev/null
  if [ $? -ne 0 ]; then
    errexit "BOOT filesystem appears corrupted"
  fi
  if [ "${ROOT_TYPE}" = "f2fs" ]; then
    mkfs.f2fs "${USB_ROOT}" > /dev/null
  else
    mkfs.ext4 -q -b 4096 "${USB_ROOT}" > /dev/null
  fi
  if [ $? -ne 0 ]; then
    errexit "Unable to create ROOT filesystem"
  fi
  mntusb
  mkdir "${MNTPATH}/dev/" "${MNTPATH}/media/" "${MNTPATH}/mnt/" "${MNTPATH}/proc/" "${MNTPATH}/run/" "${MNTPATH}/sys/" "${MNTPATH}/tmp/"
  if [ $? -ne 0 ]; then
    errexit "Unable to create directories"
  fi
  chmod a+rwxt "${MNTPATH}/tmp/"
  rsync -aDH --partial --numeric-ids --delete --force --exclude "${MNTPATH}" --exclude '/dev' --exclude '/media' --exclude '/mnt' --exclude '/proc' --exclude '/run' --exclude '/sys' \
--exclude '/tmp' --exclude 'lost\+found' --exclude '/etc/udev/rules.d/70-persistent-net.rules' --exclude '/var/lib/asterisk/astdb.sqlite3-journal' / "${MNTPATH}/"
  if [ $? -ne 0 ]; then
    errexit "Unable to replicate BOOT/ROOT contents from /dev/${ROOT_DEV} to ${USB_DEST}"
  fi
  umntusb
  echo ""
  echo "BOOT/ROOT contents replicated from /dev/${ROOT_DEV} to ${USB_DEST}"
fi

PTUUID="$(blkid "${USB_DEST}" | sed -n 's|^.*PTUUID="\(\S\+\)".*|\1|p')"

mntusb
sed -i "s|^\S\+\(\s\+/boot\s\+.*\)$|PARTUUID=${PTUUID}-01\1|" "${MNTPATH}/etc/fstab"
sed -i "s|^\S\+\(\s\+/\s\+.*\)$|PARTUUID=${PTUUID}-02\1|" "${MNTPATH}/etc/fstab"
umntusb

if [ -b /dev/mmcblk0 ]; then
  mount /dev/mmcblk0p1 /media/
  if [ $? -ne 0 ]; then
    errexit "Unable to mount BOOT partition"
  fi
  sed -i "s|^\(.*root=\)\S\+\(\s\+.*\)$|\1PARTUUID=${PTUUID}-02\2|" /media/cmdline.txt
  umount /media/
  if [ "$(blkid /dev/mmcblk0 | sed -n 's|^.*PTUUID="\(\S\+\)".*|\1|p')" = "${PTUUID}" ]; then
    echo ""
    echo "WARNING : SD card (/dev/mmcblk0) and USB device (${USB_DEST}) have the same PTUUID (${PTUUID}) : SD card will boot instead of USB device"
  fi
else
  echo ""
  echo "WARNING : SD card not present"
fi

DEV_LIST=()
if [ -b /dev/mmcblk0 ]; then
  DEV_LIST+=/dev/mmcblk0
fi
DEV_LIST+=($(ls -l /dev/sd? | sed -n 's|^.*\(/dev/.*\)|\1|p'))
if [ ${#DEV_LIST[@]} -gt 1 ]; then
  for i in ${!DEV_LIST[@]}; do
    if [ ${i} -lt $((${#DEV_LIST[@]} - 1)) ]; then
      j=$((i + 1))
      while [ ${j} -lt ${#DEV_LIST[@]} ]; do
        if [ "$(blkid "${DEV_LIST[i]}" | sed -n 's|^.*PTUUID="\(\S\+\)".*|\1|p')" = "$(blkid "${DEV_LIST[j]}" | sed -n 's|^.*PTUUID="\(\S\+\)".*|\1|p')" ];then
          if [[ "${DEV_LIST[i]}" != "/dev/mmcblk0" || "${DEV_LIST[j]}" != "${USB_DEST}" ]]; then
            echo ""
            echo "WARNING : ${DEV_LIST[i]} and ${DEV_LIST[j]} have the same PTUUID : $(blkid "${DEV_LIST[i]}" | sed -n 's|^.*PTUUID="\(\S\+\)".*|\1|p')"
          fi
        fi
      ((j += 1))
      done
    fi
  done
fi
echo ""
