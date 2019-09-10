#!/bin/bash

set -e

## BACKWARD FIXES ( for older images )

source /usr/local/etc/library.sh # sets NCVER PHPVER RELEASE

# all images

# restore sources in stretch
sed -i "s/buster/$RELEASE/g" /etc/apt/sources.list.d/* &>/dev/null || true

# restore smbclient after dist upgrade
apt-get update
apt-get install -y --no-install-recommends php${PHPVER}-gmp

# fix fail2ban with UFW only for non docker images
[[ -f /.docker-image ]] && {
cat > /etc/systemd/system/fail2ban.service.d/touch-ufw-log.conf <<EOF
}

[Service]
ExecStartPre=/bin/touch /var/log/ufw.log
EOF

# docker images only
[[ -f /.docker-image ]] && {
  :
}

# for non docker images
[[ ! -f /.docker-image ]] && {
  :
}

exit 0
