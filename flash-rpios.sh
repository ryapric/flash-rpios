#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  printf "ERROR: this script must be run as root. Aborting\n" > /dev/stderr
  exit 1
fi

device="$1"
device_short="${device//\/dev\//}"

lsblk "${device}" > /dev/null || {
  printf "ERROR: device %s is not connected. Aborting.\n" > "${device}" /dev/stderr
  exit 1
}

# Kill early if wpa_supplicant.conf can't be found
[[ -f wpa_supplicant.conf ]] || {
  printf "ERROR: no custom wpa_supplicant.conf found in this directory. Aborting.\n" > /dev/stderr
  exit 1
}

download() {
  root_url='https://downloads.raspberrypi.org/raspios_lite_armhf/images'

  # The 'L' var(s) specify the URL level -- sometimes the date stamps don't
  # match between levels, so we need to look for both/all, ending with the
  # actual zipfile containing the .img
  L1=$(curl -fsSL "${root_url}" | grep -E -o 'raspios_lite_armhf-([0-9\-]+)' | tail -n1)
  zipfile=$(curl -fsSL "${root_url}/${L1}" | grep -E -o '[0-9\-]+.*\.zip"' | sed 's/"//')

  printf "Latest discovered RPiOS file is '%s'\n" "${zipfile}"

  # Now actually download the file, if it doesn't exist
  if [[ -f "${zipfile}" ]]; then
    printf "Found local file '%s'; skipping download\n\n" "${zipfile}"
    return 0
  else
    printf "Downloading...\n\n"
    curl -fsSL -O "${root_url}/${L1}/${zipfile}"
    unzip "${zipfile}"
  fi
}

write-to-device() {
  lsblk | grep "${device_short}"
  printf "\nAbove is the block device state for the device you provided (%s).\n" "${device}"
  printf "MAKE VERY SURE that a) the device is the one you want to use, and b) IT IS UNMOUNTED\n\n"
  read -rp "Are you SURE this is the device you want to use? (y/N): " ans
  if [[ "${ans}" == 'y' ]]; then
    printf "Writing RPiOS image to %s...\n" "${device}"
    printf "Note that the progress tracker may freeze as it finalizes the write -- this is mostly normal\n"
    dd if="${zipfile//.zip/.img}" of="${device}" status=progress # bs=64M
    
    printf "Syncing disk changes...\n"
    sync
    sleep 5 # next step seems to not catch the rootfs partition fast enough, so chill here for a sec
  else
    printf "Not confirmed; aborting\n"
    exit 1
  fi
}

configure() {
  bootpart=$(lsblk --fs "${device}" | grep boot | grep -o "${device_short}[0-9]")
  rootfspart=$(lsblk --fs "${device}" | grep rootfs | grep -o "${device_short}[0-9]")
  
  printf "Making mountpoints for RPiOS...\n"
  mkdir -p /tmp/rpios/{boot,rootfs}
  mount /dev/"${bootpart}" /tmp/rpios/boot
  mount /dev/"${rootfspart}" /tmp/rpios/rootfs

  printf "Adding empty 'ssh' file to boot partition, to enable SSH at boot...\n"
  touch /tmp/rpios/boot/ssh

  printf "Adding wpa_supplicant.conf to boot partition, to (hopefully) enable WiFi connection at boot...\n"
  printf "Contents of wpa_supplicant.conf:\n"
  cat ./wpa_supplicant.conf
  cp ./wpa_supplicant.conf /tmp/rpios/boot/wpa_supplicant.conf
  
  printf "Configuring to request static IP address of 192.168.1.100...\n"
  printf "interface wlan0\n\tstatic ip_address=192.168.1.100/24\n\tstatic routers=192.168.1.1\n" | tee -a /tmp/rpios/rootfs/etc/dhcpcd.conf > /dev/null
  
  printf "Syncing disk changes...\n"
  sync
  
  printf "Unmounting RPiOS partitions...\n"
  umount -R /tmp/rpios/*
}

main() {
  download
  write-to-device
  configure
}

main
