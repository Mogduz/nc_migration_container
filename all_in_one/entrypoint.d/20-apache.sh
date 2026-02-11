#!/usr/bin/env bash
set -euo pipefail

log "Running 20-apache.sh"
log "Configuring Apache for Nextcloud"
sed -i 's#DocumentRoot /var/www/html#DocumentRoot /var/www/html/nextcloud#' /etc/apache2/sites-available/000-default.conf
cat > /etc/apache2/conf-available/nextcloud.conf <<'CONF'
<Directory /var/www/html/nextcloud>
  Require all granted
  AllowOverride All
  Options FollowSymLinks MultiViews
</Directory>
CONF
cat > /etc/apache2/conf-available/nextcloud-redirect.conf <<'CONF'
RedirectMatch 302 ^/nextcloud/?$ /
CONF
a2enconf nextcloud >/dev/null
a2enconf nextcloud-redirect >/dev/null
