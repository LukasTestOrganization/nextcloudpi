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

# rename DDNS entries TODO temporary
[[ -f "$CONFDIR"/no-ip.sh ]] && {
  mv "$CONFDIR"/no-ip.sh   "$CONFDIR"/DDNS_no-ip.sh
  mv "$CONFDIR"/freeDNS.sh "$CONFDIR"/DDNS_freeDNS.sh
  mv "$CONFDIR"/duckDNS.sh "$CONFDIR"/DDNS_duckDNS.sh
  mv "$CONFDIR"/spDYN.sh   "$CONFDIR"/DDNS_spDYN.sh
}

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

[[ -f /.docker-image ]] && {
  # remove unwanted packages for the docker version
  for opt in $EXCL_DOCKER; do rm $CONFDIR/$opt; done

  # update services
  cp docker-common/{lamp/010lamp,nextcloud/020nextcloud,nextcloudpi/000ncp} /etc/services-available.d

}

## BACKWARD FIXES ( for older images )

# not for image builds, only live updates
[[ ! -f /.ncp-image ]] && {

  # docker images only
  [[ -f /.docker-image ]] && {
    [[ -e /data/etc/live ]] && {
     cat > /etc/services-available.d/000ncp <<EOF
#!/bin/bash

source /usr/local/etc/library.sh

# INIT NCP CONFIG (first run)
persistent_cfg /usr/local/etc/ncp-config.d /data/ncp
persistent_cfg /etc/services-enabled.d
persistent_cfg /etc/letsencrypt                    # persist SSL certificates
persistent_cfg /etc/shadow                         # persist ncp-web password
persistent_cfg /etc/cron.d
persistent_cfg /etc/cron.daily
persistent_cfg /etc/cron.hourly
persistent_cfg /etc/cron.weekly

exit 0
EOF
      /etc/services-available.d/000ncp
      rm /data/etc/letsencrypt/live
      mv /data/etc/live /data/etc/letsencrypt
    }
  }

  # for non docker images
  [[ ! -f /.docker-image ]] && {
    # fix locale for Armbian images, for ncp-config
    [[ "$LANG" == "" ]] && localectl set-locale LANG=en_US.utf8
  }

  # no-origin policy for enhanced privacy
  grep -q "Referrer-Policy" /etc/apache2/apache2.conf || {
    cat >> /etc/apache2/apache2.conf <<EOF
<IfModule mod_headers.c>
  Header always set Referrer-Policy "no-referrer"
</IfModule>
EOF
  }

  # NC14 doesnt support php mail
  mail_smtpmode=$(sudo -u www-data php /var/www/nextcloud/occ config:system:get mail_smtpmode)
  [[ $mail_smtpmode == "php" ]] && {
    sudo -u www-data php /var/www/nextcloud/occ config:system:set mail_smtpmode --value="sendmail"
  }

  # update nc-restore
  cd "$CONFDIR" &>/dev/null
  install_script nc-backup.sh
  install_script nc-restore.sh
  cd -          &>/dev/null

  # install preview generator
  sudo -u www-data php /var/www/nextcloud/occ app:install previewgenerator
  sudo -u www-data php /var/www/nextcloud/occ app:enable  previewgenerator

  # use separate db config file
  [[ -f /etc/mysql/mariadb.conf.d/90-ncp.cnf ]] || {
    cp /etc/mysql/mariadb.conf.d/50-server.cnf /etc/mysql/mariadb.conf.d/90-ncp.cnf
    service mysql restart
  }

  # update to NC14.0.1
  F="$CONFDIR"/nc-autoupdate-nc.sh
  grep -q '^ACTIVE_=yes$' "$F" && {
    cd "$CONFDIR" &>/dev/null
    activate_script nc-autoupdate-nc.sh
    cd -          &>/dev/null
  }

  # fix locale for Armbian images, for ncp-config
  [[ "$LANG" == "" ]] && localectl set-locale LANG=en_US.utf8

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

