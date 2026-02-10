# Base image
FROM ubuntu:20.04

# Prevent interactive prompts during install
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies + Nextcloud 25 prerequisites
# - Apache 2.4
# - PHP 7.4 (supported by Nextcloud 25; 7.4 is deprecated upstream)
# - Required PHP modules per Nextcloud 25 admin manual
# - Recommended PHP modules (bz2, intl)
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

# Enable Apache modules required by Nextcloud
RUN a2enmod rewrite headers env dir mime

# Configure Apache to serve Nextcloud at /
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

# Download and install Nextcloud 25 at build time (fixed version)
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

# Move initial config to external path and symlink it
RUN set -eux; \
    mkdir -p /mnt/NextCloud/config; \
    cp -a /var/www/html/nextcloud/config/. /mnt/NextCloud/config/; \
    rm -rf /var/www/html/nextcloud/config; \
    ln -s /mnt/NextCloud/config /var/www/html/nextcloud/config

# Entrypoint for initialization (SQLite)
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
    && printf '%s\n' '#!/usr/bin/env bash' 'exec php /var/www/html/nextcloud/occ "$@"' > /usr/local/bin/occ \
    && chmod +x /usr/local/bin/occ

# Expose HTTP
EXPOSE 80

# Create app directory
WORKDIR /app

# Copy application files (adjust as needed)
# COPY . /app

# Install app dependencies (placeholder)
# RUN ./install.sh

# Expose service port (placeholder)
# EXPOSE 8080

# Initialize on first start, then run Apache
ENTRYPOINT ["/entrypoint.sh"]
CMD ["apachectl", "-D", "FOREGROUND"]
