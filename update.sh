#!/bin/bash

# Updater for NextCloudPi
#
# Copyleft 2017 by Ignacio Nunez Hernanz <nacho _a_t_ ownyourbits _d_o_t_ com>
# GPL licensed (see end of file) * Use at your own risk!
#
# More at https://ownyourbits.com/
#

CONFDIR=/usr/local/etc/ncp-config.d/

# don't make sense in a docker container
EXCL_DOCKER="
nc-automount.sh
nc-format-USB.sh
nc-datadir.sh
nc-database.sh
nc-ramlogs.sh
nc-swapfile.sh
nc-static-IP.sh
nc-wifi.sh
nc-nextcloud.sh
nc-init.sh
UFW.sh
nc-snapshot.sh
nc-snapshot-auto.sh
nc-audit.sh
SSH.sh
fail2ban.sh
NFS.sh
"

# better use a designated container
EXCL_DOCKER+="
samba.sh
"

# check running apt
pgrep apt &>/dev/null && { echo "apt is currently running. Try again later";  exit 1; }

cp etc/library.sh /usr/local/etc/

source /usr/local/etc/library.sh

mkdir -p "$CONFDIR"

# prevent installing some apt packages in the docker version
[[ -f /.docker-image ]] && {
  for opt in $EXCL_DOCKER; do 
    touch $CONFDIR/$opt
done
}

# copy all files in bin and etc
for file in bin/* etc/*; do
  [ -f "$file" ] || continue;
  cp "$file" /usr/local/"$file"
done

# install new entries of ncp-config and update others
for file in etc/ncp-config.d/*; do
  [ -f "$file" ] || continue;    # skip dirs
  [ -f /usr/local/"$file" ] || { # new entry
    install_script "$file"       # install

    # configure if active by default
    grep -q '^ACTIVE_=yes$' "$file" && activate_script "$file" 
  }

  # save current configuration to (possibly) updated script
  [ -f /usr/local/"$file" ] && {
    VARS=( $( grep "^[[:alpha:]]\+_=" /usr/local/"$file" | cut -d= -f1 ) )
    VALS=( $( grep "^[[:alpha:]]\+_=" /usr/local/"$file" | cut -d= -f2 ) )
    for i in $( seq 0 1 ${#VARS[@]} ); do
      sed -i "s|^${VARS[$i]}=.*|${VARS[$i]}=${VALS[$i]}|" "$file"
    done
  }

  cp "$file" /usr/local/"$file"
done

# install localization files
cp -rT etc/ncp-config.d/l10n "$CONFDIR"/l10n

# these files can contain sensitive information, such as passwords
chown -R root:www-data "$CONFDIR"
chmod 660 "$CONFDIR"/*
chmod 750 "$CONFDIR"/l10n

# install web interface
cp -r ncp-web /var/www/
chown -R www-data:www-data /var/www/ncp-web
chmod 770                  /var/www/ncp-web

# remove unwanted packages for the docker version
[[ -f /.docker-image ]] && {
  for opt in $EXCL_DOCKER; do 
    rm $CONFDIR/$opt
done
}

## BACKWARD FIXES ( for older images )

# not for image builds, only live updates
[[ ! -f /.ncp-image ]] && {

  # Update btrfs-sync
  wget -q https://raw.githubusercontent.com/nachoparker/btrfs-sync/master/btrfs-sync -O /usr/local/bin/btrfs-sync
  chmod +x /usr/local/bin/btrfs-sync

  # docker images only
  [[ -f /.docker-image ]] && {
    # install curl for dynDNS and duckDNS
    [[ -f /usr/bin/curl ]] || {
      apt-get update
      apt-get install -y --no-install-recommends curl
    }
  }
  # for non docker images
  [[ ! -f /.docker-image ]] && {
    # install avahi-daemon in armbian images
    [[ -f /lib/systemd/system/avahi-daemon.service ]] || {
      apt-get update
      apt-get install -y --no-install-recommends avahi-daemon
    }
  }

  # fix wrong user for notifications
  DATADIR="$( grep datadirectory /var/www/nextcloud/config/config.php | awk '{ print $3 }' | grep -oP "[^']*[^']" | head -1 )"
  test -d "$DATADIR" && {
    [[ -d "$DATADIR"/ncp ]] && [[ ! -d "$DATADIR"/admin ]] && {
      F="$CONFDIR"/nc-notify-updates.sh
      grep -q '^USER_=admin$' "$F" && grep -q '^ACTIVE_=yes$' "$F" && {
        sed -i 's|^USER_=admin|USER_=ncp|' "$F"
        cd "$CONFDIR" &>/dev/null
        activate_script nc-notify-updates.sh
        cd -          &>/dev/null
      }
      F="$CONFDIR"/nc-autoupdate-ncp.sh
      grep -q '^NOTIFYUSER_=admin$' "$F" && grep -q '^ACTIVE_=yes$' "$F" && {
        sed -i 's|^NOTIFYUSER_=admin|NOTIFYUSER_=ncp|' "$F"
        cd "$CONFDIR" &>/dev/null
        activate_script nc-autoupdate-ncp.sh
        cd -          &>/dev/null
      }
    }
  }

  # update nc-backup and nc-restore
  cd "$CONFDIR" &>/dev/null
  install_script nc-backup.sh
  install_script nc-restore.sh
  cd -          &>/dev/null

  # fix exit status autoupdate
  F="$CONFDIR"/nc-autoupdate-ncp.sh
  grep -q '^ACTIVE_=yes$' "$F" && {
    cd "$CONFDIR" &>/dev/null
    activate_script nc-autoupdate-ncp.sh
    cd -          &>/dev/null
  }
  F="$CONFDIR"/nc-autoupdate-nc.sh
  grep -q '^ACTIVE_=yes$' "$F" && {
    cd "$CONFDIR" &>/dev/null
    activate_script nc-autoupdate-nc.sh
    cd -          &>/dev/null
  }

  # fix update httpd log location in virtual host after nc-datadir
  sed -i "s|CustomLog.*|CustomLog /var/log/apache2/nc-access.log combined|" /etc/apache2/sites-available/nextcloud.conf
  sed -i "s|ErrorLog .*|ErrorLog  /var/log/apache2/nc-error.log|"           /etc/apache2/sites-available/nextcloud.conf

  # fix systemd timer still present
  [[ -f /etc/systemd/system/nc-scan.service ]] && {
    systemctl stop nc-scan.service
    systemctl disable nc-scan.service
    rm -f /etc/systemd/system/nc-scan.service
    F="$CONFDIR"/nc-scan-auto.sh
    grep -q '^ACTIVE_=yes$' "$F" && {
      cd "$CONFDIR" &>/dev/null
      activate_script nc-scan-auto.sh
      cd -          &>/dev/null
    }
  }
  [[ -f /etc/systemd/system/nc-scan.timer ]] && {
    systemctl stop nc-scan.timer
    systemctl disable nc-scan.timer
    rm -f /etc/systemd/system/nc-scan.timer
  }
  [[ -f /etc/systemd/system/nc-backup.service ]] && {
    systemctl stop nc-backup
    systemctl disable nc-backup
    rm -f /etc/systemd/system/nc-backup.service
    F="$CONFDIR"/nc-backup-auto.sh
    grep -q '^ACTIVE_=yes$' "$F" && {
      cd "$CONFDIR" &>/dev/null
      activate_script nc-backup-auto.sh
      cd -          &>/dev/null
    }
  }
  [[ -f /etc/systemd/system/freedns.service ]] && {
    systemctl stop freedns
    systemctl disable freedns
    rm -f /etc/systemd/system/freedns.service
    F="$CONFDIR"/freeDNS.sh
    grep -q '^ACTIVE_=yes$' "$F" && {
      cd "$CONFDIR" &>/dev/null
      activate_script freeDNS.sh
      cd -          &>/dev/null
    }
  }
  [[ -f /etc/systemd/system/nc-notify-updates.service ]] && {
    systemctl stop nc-notify-updates
    systemctl disable nc-notify-updates
    rm -f /etc/systemd/system/nc-notify-updates.service
    F="$CONFDIR"/nc-notify-updates.sh
    grep -q '^ACTIVE_=yes$' "$F" && {
      cd "$CONFDIR" &>/dev/null
      activate_script nc-notify-updates.sh
      cd -          &>/dev/null
    }
  }
  [[ -f /etc/systemd/system/nc-notify-updates.timer ]] && {
    systemctl stop nc-notify-updates.timer
    systemctl disable nc-notify-updates.timer
    rm -f /etc/systemd/system/nc-notify-updates.timer
  }

  # Update files after re-renaming to NCPi
  sed -i 's|NextCloudPlus automatically|NextCloudPi automatically|' /etc/samba/smb.conf
  sed -i 's|NextCloudPlus autogenerated|NextCloudPi autogenerated|' /etc/dhcpcd.conf
  sed -i 's|NextCloudPlus|NextCloudPi|' /etc/fail2ban/action.d/sendmail-whois-lines.conf

  # make sure provisioning is enabled
  systemctl -q is-enabled nc-provisioning || {
    systemctl start nc-provisioning
    systemctl enable nc-provisioning
  }

} # end - only live updates

exit 0

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

