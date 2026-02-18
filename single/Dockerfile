# Base image:
# Ubuntu 20.04 wird hier bewusst als stabile, bekannte Basis fuer den
# kurzfristigen Migrationskontext verwendet.
FROM ubuntu:20.04

# Verhindert interaktive APT-Dialoge waehrend des Build-Prozesses.
ENV DEBIAN_FRONTEND=noninteractive

# Installation aller benoetigten Pakete:
# - Webserver (Apache)
# - PHP 7.4 + Nextcloud-relevante Extensions
# - Basis-Tools zum Downloaden, Entpacken und Verifizieren von Releases
# Hinweis: PHP 7.4 ist fuer Nextcloud 25 passend, aber generell veraltet.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    apache2 \
    libapache2-mod-php7.4 \
    php7.4-cli \
    php7.4-common \
    php7.4-ctype \
    php7.4-curl \
    php7.4-dom \
    php7.4-fileinfo \
    php7.4-gd \
    php7.4-json \
    php7.4-mbstring \
    php7.4-xml \
    php7.4-zip \
    php7.4-opcache \
    php7.4-pdo \
    php7.4-mysql \
    php7.4-pgsql \
    php7.4-sqlite3 \
    php7.4-bz2 \
    php7.4-intl \
    libxml2 \
    zlib1g \
    bzip2 \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Aktiviert Apache-Module, die fuer Nextcloud-Funktionen noetig sind
# (u. a. URL-Rewrite und Header-Handling).
RUN a2enmod rewrite headers env dir mime

# Apache-Konfiguration:
# - DocumentRoot direkt auf /var/www/html/nextcloud setzen
# - Zugriff und .htaccess-Verarbeitung fuer Nextcloud erlauben
# - Redirect von /nextcloud nach / fuer saubere URL-Basis
RUN set -eux; \
    sed -i 's#DocumentRoot /var/www/html#DocumentRoot /var/www/html/nextcloud#' /etc/apache2/sites-available/000-default.conf; \
    printf '%s\n' \
      '<Directory /var/www/html/nextcloud>' \
      '  Require all granted' \
      '  AllowOverride All' \
      '  Options FollowSymLinks MultiViews' \
      '</Directory>' \
      > /etc/apache2/conf-available/nextcloud.conf; \
    printf '%s\n' \
      'RedirectMatch 302 ^/nextcloud/?$ /' \
      > /etc/apache2/conf-available/nextcloud-redirect.conf; \
    a2enconf nextcloud; \
    a2enconf nextcloud-redirect

# Nextcloud wird bereits beim Build heruntergeladen:
# - feste Version per Build-Argument
# - SHA256-Pruefung vor dem Entpacken
# - Initiales Datenverzeichnis und Dateirechte vorbereiten
ARG NC_VERSION=25.0.0
ENV NC_VERSION=${NC_VERSION}
RUN set -eux; \
    curl -fsSLO "https://download.nextcloud.com/server/releases/nextcloud-${NC_VERSION}.tar.bz2"; \
    curl -fsSLO "https://download.nextcloud.com/server/releases/nextcloud-${NC_VERSION}.tar.bz2.sha256"; \
    sha256sum -c "nextcloud-${NC_VERSION}.tar.bz2.sha256"; \
    tar -xjf "nextcloud-${NC_VERSION}.tar.bz2" -C /var/www/html/; \
    mkdir -p /var/www/html/nextcloud/data; \
    chown -R www-data:www-data /var/www/html/nextcloud; \
    rm -f "nextcloud-${NC_VERSION}.tar.bz2" "nextcloud-${NC_VERSION}.tar.bz2.sha256"

# Konfiguration aus dem Containerpfad auslagern:
# - initiale config nach /mnt/NextCloud/config kopieren
# - Original ersetzen durch Symlink auf den Mountpunkt
# So bleibt config.php ueber Container-Neustarts hinweg erhalten.
RUN set -eux; \
    mkdir -p /mnt/NextCloud/config; \
    cp -a /var/www/html/nextcloud/config/. /mnt/NextCloud/config/; \
    rm -rf /var/www/html/nextcloud/config; \
    ln -s /mnt/NextCloud/config /var/www/html/nextcloud/config

# Entry-Skript fuer Initialisierung (u. a. optionales SQLite-Setup).
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
    && printf '%s\n' '#!/usr/bin/env bash' 'exec php /var/www/html/nextcloud/occ "$@"' > /usr/local/bin/occ \
    && chmod +x /usr/local/bin/occ

# HTTP-Port im Container.
EXPOSE 80

# Arbeitsverzeichnis (hier derzeit ohne weitere App-Dateien genutzt).
WORKDIR /app

# Platzhalter fuer eventuelle zusaetzliche Anwendungsdateien.
# COPY . /app

# Platzhalter fuer optionale Zusatz-Installationsschritte.
# RUN ./install.sh

# Platzhalter fuer weitere Ports, falls spaeter erforderlich.
# EXPOSE 8080

# Beim Start wird zuerst das Entrypoint-Skript ausgefuehrt,
# anschliessend Apache im Vordergrund gestartet.
ENTRYPOINT ["/entrypoint.sh"]
CMD ["apachectl", "-D", "FOREGROUND"]
