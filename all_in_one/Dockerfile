# Base image
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies + services
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
    php7.4-apcu \
    php-redis \
    libxml2 \
    zlib1g \
    bzip2 \
    unzip \
    mariadb-server \
    redis-server \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# Enable Apache modules required by Nextcloud
RUN a2enmod rewrite headers env dir mime

# Enable APCu in CLI (required for occ)
RUN printf '%s\n' 'apc.enable_cli=1' > /etc/php/7.4/cli/conf.d/99-apcu-cli.ini

# Download and install Nextcloud at build time (override with --build-arg NC_VERSION)
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

# Ensure config directory exists (will be bind-mounted at runtime)
RUN set -eux; \
    mkdir -p /var/www/html/nextcloud/config; \
    chown -R www-data:www-data /var/www/html/nextcloud/config

# Entrypoint for initialization
COPY entrypoint.sh /entrypoint.sh
COPY entrypoint.d /entrypoint.d
RUN chmod +x /entrypoint.sh \
    && printf '%s\n' '#!/usr/bin/env bash' 'exec php /var/www/html/nextcloud/occ "$@"' > /usr/local/bin/occ \
    && chmod +x /usr/local/bin/occ

# Supervisor configuration
COPY supervisor.conf /etc/supervisor/conf.d/supervisor.conf
COPY healthcheck.sh /healthcheck.sh
RUN chmod +x /healthcheck.sh

EXPOSE 80 3306 6379

WORKDIR /app

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]

HEALTHCHECK --interval=10s --timeout=5s --start-period=120s --retries=3 CMD ["/healthcheck.sh"]
