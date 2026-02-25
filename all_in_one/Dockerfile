# Basisimage fuer die kombinierte Migrationsumgebung.
FROM ubuntu:20.04

# Deaktiviert interaktive Paketdialoge.
ENV DEBIAN_FRONTEND=noninteractive

# Build-Profil fuer APT-Quellen:
# - normal: unveraenderte Ubuntu-Repositories
# - ldbv:   Repositories aus apt/ldbv.sources.list waehrend des Builds
ARG APT_PROFILE=normal
COPY apt/ldbv.sources.list /tmp/ldbv.sources.list

# Installiert alle benoetigten Dienste in einem Image:
# - Apache + PHP fuer Nextcloud
# - MySQL 8 fuer Datenbankimport/Upgrade
# - Redis fuer Caching/Locking
# - Supervisor zur Prozesssteuerung mehrerer Dienste
RUN set -eux; \
    case "${APT_PROFILE}" in \
      normal) \
        ;; \
      ldbv) \
        if ! grep -Eq '^[[:space:]]*deb[[:space:]]+' /tmp/ldbv.sources.list; then \
          echo "APT_PROFILE=ldbv erfordert mindestens einen gueltigen 'deb'-Eintrag in apt/ldbv.sources.list" >&2; \
          exit 1; \
        fi; \
        cp /tmp/ldbv.sources.list /etc/apt/sources.list; \
        find /etc/apt/sources.list.d -mindepth 1 -maxdepth 1 -type f \( -name '*.list' -o -name '*.sources' \) -delete; \
        ;; \
      *) \
        echo "Ungueltiges APT_PROFILE: '${APT_PROFILE}' (erlaubt: normal, ldbv)" >&2; \
        exit 1; \
        ;; \
    esac; \
    apt-get update && apt-get install -y --no-install-recommends \
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
    php7.4-apcu \
    php-redis \
    libxml2 \
    zlib1g \
    bzip2 \
    unzip \
    mysql-server-8.0 \
    redis-server \
    supervisor \
    && rm -rf /var/lib/apt/lists/* /tmp/ldbv.sources.list

# Laufzeitverzeichnis fuer mysqld sicherstellen.
RUN set -eux; \
    mkdir -p /var/run/mysqld; \
    chown -R mysql:mysql /var/run/mysqld /var/lib/mysql

# Aktiviert notwendige Apache-Module fuer Nextcloud.
RUN a2enmod rewrite headers env dir mime

# Aktiviert APCu auch fuer CLI-Aufrufe; wichtig fuer `occ`.
RUN printf '%s\n' 'apc.enable_cli=1' > /etc/php/7.4/cli/conf.d/99-apcu-cli.ini

# Nextcloud wird fest versioniert im Build gezogen und geprueft.
# NC_VERSION kann bei Bedarf per --build-arg ueberschrieben werden.
ARG NC_VERSION=25.0.13
ENV NC_VERSION=${NC_VERSION}
RUN set -eux; \
    curl -fsSLO "https://download.nextcloud.com/server/releases/nextcloud-${NC_VERSION}.tar.bz2"; \
    curl -fsSLO "https://download.nextcloud.com/server/releases/nextcloud-${NC_VERSION}.tar.bz2.sha256"; \
    sha256sum -c "nextcloud-${NC_VERSION}.tar.bz2.sha256"; \
    tar -xjf "nextcloud-${NC_VERSION}.tar.bz2" -C /var/www/html/; \
    mkdir -p /var/www/html/nextcloud/data; \
    chown -R www-data:www-data /var/www/html/nextcloud; \
    rm -f "nextcloud-${NC_VERSION}.tar.bz2" "nextcloud-${NC_VERSION}.tar.bz2.sha256"

# Konfigurationsverzeichnis anlegen; wird typischerweise per Bind-Mount ersetzt.
RUN set -eux; \
    mkdir -p /var/www/html/nextcloud/config; \
    chown -R www-data:www-data /var/www/html/nextcloud/config

# Entry-Skripte und Migrations-Helper in das Image kopieren.
COPY entrypoint.sh /entrypoint.sh
COPY entrypoint.d /entrypoint.d
COPY migrate.sh /usr/local/bin/migrate.sh
RUN chmod +x /entrypoint.sh \
    && chmod +x /usr/local/bin/migrate.sh \
    && printf '%s\n' '#!/usr/bin/env bash' 'exec php /var/www/html/nextcloud/occ "$@"' > /usr/local/bin/occ \
    && chmod +x /usr/local/bin/occ

# Supervisor- und Healthcheck-Konfiguration.
COPY supervisor.conf /etc/supervisor/conf.d/supervisor.conf
COPY healthcheck.sh /healthcheck.sh
RUN chmod +x /healthcheck.sh

# Exponierte Ports:
# - 80   Apache
# - 3306 MySQL (intern i. d. R. localhost)
# - 6379 Redis
EXPOSE 80 3306 6379

# Arbeitsverzeichnis fuer zusaetzliche manuelle Schritte.
WORKDIR /app

# Entry und Startkommando:
# Supervisor startet und ueberwacht Apache, MySQL und Redis.
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]

# Healthcheck auf lokale HTTP-Erreichbarkeit.
HEALTHCHECK --interval=10s --timeout=5s --start-period=120s --retries=3 CMD ["/healthcheck.sh"]
