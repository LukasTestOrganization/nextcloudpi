#!/bin/bash

set -e

## BACKWARD FIXES ( for older images )

source /usr/local/etc/library.sh

# not for image builds, only live updates
[[ ! -f /.ncp-image ]] && {

  # docker images only
  [[ -f /.docker-image ]] && {
    :
  }

  # for non docker images
  [[ ! -f /.docker-image ]] && {
    cat > /etc/fail2ban/filter.d/ufwban.conf <<'EOF'
[INCLUDES]
before = common.conf
[Definition]
failregex = UFW BLOCK.* SRC=
ignoreregex =
EOF
    :
  }

  # remove files that have been moved
  rm -f "$BINDIR"/CONFIG/nc-notify-updates.sh
  rm -f "$BINDIR"/TOOLS/nc-update-nc-apps.sh
  rm -f "$BINDIR"/TOOLS/nc-update-nextcloud.sh
  rm -f "$BINDIR"/TOOLS/nc-update.sh
  rm -f "$BINDIR"/{SYSTEM/unattended-upgrades.sh,CONFIG/nc-autoupdate-nc.sh,CONFIG/nc-autoupdate-ncp.sh,CONFIG/nc-update-nc-apps-auto.sh}

  # previews settings
  ncc config:app:set previewgenerator squareSizes --value="32"
  ncc config:app:set previewgenerator widthSizes  --value="128 256 512"
  ncc config:app:set previewgenerator heightSizes --value="128 256"
  ncc config:system:set jpeg_quality --value 60

  # update unattended labels
  is_active_app unattended-upgrades && run_app unattended-upgrades

  # update sury keys
  wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg

  # fix cron path
  is_active_app nc-backup-auto && run_app nc-backup-auto
  is_active_app nc-scan-auto && run_app nc-scan-auto
  is_active_app nc-autoupdate-ncp && run_app nc-autoupdate-ncp
  is_active_app nc-notify-updates && run_app nc-notify-updates
  is_active_app nc-previews-auto && run_app nc-previews-auto
  is_active_app nc-update-nc-apps-auto && run_app nc-update-nc-apps-auto

  # rework letsencrypt notification
  USER="$(jq -r '.params[2].value' "$CFGDIR"/letsencrypt.cfg)"
  mkdir -p /etc/letsencrypt/renewal-hooks/deploy/
  cat > /etc/letsencrypt/renewal-hooks/deploy/ncp <<EOF
#!/bin/bash
/usr/local/bin/ncc notification:generate $USER "SSL renewal" -l "Your SSL certificate(s) \$RENEWED_DOMAINS has been renewed for another 90 days"
EOF
  chmod +x /etc/letsencrypt/renewal-hooks/deploy/ncp

  # update nc-backup
  install_app nc-backup
  install_app nc-restore

  # create UPDATES section
  updates_dir=/usr/local/bin/ncp/UPDATES
  mkdir -p "$updates_dir"
  (
  mv /usr/local/bin/ncp/{SYSTEM/unattended-upgrades.sh,CONFIG/nc-autoupdate-nc.sh,CONFIG/nc-autoupdate-ncp.sh,CONFIG/nc-update-nc-apps-auto.sh} "$updates_dir" || true
  mv /usr/local/bin/ncp/TOOLS/{nc-update-nc-apps,nc-update-nextcloud,nc-update}.sh "$updates_dir" || true
  mv /usr/local/bin/ncp/CONFIG/nc-notify-updates.sh "$updates_dir" || true
  ) &>/dev/null

  # armbian fix uu
  rm -f /etc/apt/apt.conf.d/02-armbian-periodic

  # switch back to the apt LE version
  which letsencrypt &>/dev/null || install_app letsencrypt

  # update launchers
  apt-get update
  apt_install file
  cat > /home/www/ncp-launcher.sh <<'EOF'
#!/bin/bash
grep -q '[\\&#;`|*?~<>^()[{}$&[:space:]]' <<< "$*" && exit 1
source /usr/local/etc/library.sh
run_app $1
EOF
  chmod 700 /home/www/ncp-launcher.sh

  cat > /home/www/ncp-backup-launcher.sh <<'EOF'
#!/bin/bash
action="${1}"
file="${2}"
compressed="${3}"
grep -q '[\\&#;`|*?~<>^()[{}$&]' <<< "$*" && exit 1
[[ "$file" =~ ".." ]] && exit 1
[[ "${action}" == "chksnp" ]] && {
  btrfs subvolume show "$file" &>/dev/null || exit 1
  exit
}
[[ "${action}" == "delsnp" ]] && {
  btrfs subvolume delete "$file" || exit 1
  exit
}
[[ -f "$file" ]] || exit 1
[[ "$file" =~ ".tar" ]] || exit 1
[[ "${action}" == "del" ]] && {
  [[ "$(file "$file")" =~ "tar archive" ]] || [[ "$(file "$file")" =~ "gzip compressed data" ]] || exit 1
  rm "$file" || exit 1
  exit
}
[[ "$compressed" != "" ]] && pigz="-I pigz"
tar $pigz -tf "$file" data &>/dev/null
EOF
  chmod 700 /home/www/ncp-backup-launcher.sh
  sed -i 's|www-data ALL = NOPASSWD: .*|www-data ALL = NOPASSWD: /home/www/ncp-launcher.sh , /home/www/ncp-backup-launcher.sh, /sbin/halt, /sbin/reboot|' /etc/sudoers

  # fix logrotate files
  chmod 0444 /etc/logrotate.d/*

  # adjust preview sizes
  [[ "$(ncc config:system:get preview_max_x)" == "" ]] && {
    ncc config:app:set previewgenerator squareSizes --value="32 256"
    ncc config:app:set previewgenerator widthSizes  --value="256 384"
    ncc config:app:set previewgenerator heightSizes --value="256"
    ncc config:system:set preview_max_x --value 2048
    ncc config:system:set preview_max_y --value 2048
    ncc config:system:set jpeg_quality --value 60
  }

  # adjust local IPv6
  cat > /etc/apache2/sites-available/ncp.conf <<EOF
Listen 4443
<VirtualHost _default_:4443>
  DocumentRoot /var/www/ncp-web
  SSLEngine on
  SSLCertificateFile      /etc/ssl/certs/ssl-cert-snakeoil.pem
  SSLCertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key

  # 2 days to avoid very big backups requests to timeout
  TimeOut 172800

  <IfModule mod_authnz_external.c>
    DefineExternalAuth pwauth pipe /usr/sbin/pwauth
  </IfModule>

</VirtualHost>
<Directory /var/www/ncp-web/>

  AuthType Basic
  AuthName "ncp-web login"
  AuthBasicProvider external
  AuthExternal pwauth

  SetEnvIf Request_URI "^" noauth
  SetEnvIf Request_URI "^index\.php$" !noauth
  SetEnvIf Request_URI "^/$" !noauth
  SetEnvIf Request_URI "^/wizard/index.php$" !noauth
  SetEnvIf Request_URI "^/wizard/$" !noauth

  <RequireAll>

   <RequireAny>
      Require host localhost
      Require local
      Require ip 192.168
      Require ip 172
      Require ip 10
      Require ip fd00::/8
      Require ip fe80::/10
   </RequireAny>

   <RequireAny>
      Require env noauth
      Require user ncp
   </RequireAny>

  </RequireAll>

</Directory>
EOF

  # remove redundant opcache configuration. Leave until update bug is fixed -> https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=815968
  # Bug #416 reappeared after we moved to php7.2 and debian buster packages. (keep last)
  [[ "$( ls -l /etc/php/7.2/fpm/conf.d/*-opcache.ini |  wc -l )" -gt 1 ]] && rm "$( ls /etc/php/7.2/fpm/conf.d/*-opcache.ini | tail -1 )"
  [[ "$( ls -l /etc/php/7.2/cli/conf.d/*-opcache.ini |  wc -l )" -gt 1 ]] && rm "$( ls /etc/php/7.2/cli/conf.d/*-opcache.ini | tail -1 )"

} # end - only live updates

exit 0
