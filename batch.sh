#!/bin/bash

# Batch creation of NextCloudPi images and containers
#
# Copyleft 2017 by Ignacio Nunez Hernanz <nacho _a_t_ ownyourbits _d_o_t_ com>
# GPL licensed (see end of file) * Use at your own risk!
#
# Usage: ./batch.sh <DHCP QEMU image IP>
#

set -e

IP=${1:-192.168.0.145}      # For QEMU automated testing

## BUILDING
source buildlib.sh          # initializes $IMGNAME

[[ "$FTPPASS" == "" ]] && {
  echo -e "\e[1mNo FTPPASS variable found, FTP won't work.\nYou can to cancel now\e[0m"
  sleep 5
}

# Raspbian
./build-SD-rpi.sh "$IP"
# TODO berryboot

# Armbian
./build-SD-armbian.sh odroidxu4 OdroidHC2
./build-SD-armbian.sh rock64
./build-SD-armbian.sh bananapi

# Docker x86
docker pull debian:stretch-slim
make nextcloudpi-x86 && {
  docker push ownyourbits/nextcloudpi-x86 
  docker push ownyourbits/nextcloud-x86 
  docker push ownyourbits/lamp-x86
  docker push ownyourbits/debian-ncp-x86
}

# docker armhf
[[ -f docker-armhf/raspbian_docker.img ]] || \
  ./installer.sh docker-armhf/docker-env.sh "$IP" raspbian_lite.img # && mv
./installer.sh docker-armhf/build-container.sh "$IP" docker-armhf/raspbian_docker.img

# License
#
# This script is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This script is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this script; if not, write to the
# Free Software Foundation, Inc., 59 Temple Place, Suite 330,
# Boston, MA  02111-1307  USA
