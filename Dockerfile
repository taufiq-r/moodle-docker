ARG ENVIRONMENT=production

FROM php:8.4-fpm-alpine AS base

# Install runtime dependencies 
RUN --mount=type=cache,target=/var/cache/apk \
    apk add --no-cache \
        bash \
        curl \
        git \
        gettext \
        icu-libs \
        libpng \
        libjpeg \
        libxml2 \
        libzip \
        postgresql-client \
        unzip \
        wget

# Install PHP extensions 
RUN --mount=type=cache,target=/var/cache/apk \
    apk add --no-cache --virtual .build-deps \
    autoconf g++ make \
        icu-dev \
        libpng-dev \
        libjpeg-turbo-dev \
        libpq-dev \
        libxml2-dev \
        libzip-dev \
    && docker-php-ext-configure gd --with-jpeg \
    && docker-php-ext-install \
        exif \
        gd \
        intl \
        opcache \
        pdo_pgsql \
        pgsql \
        soap \
        zip \
    && apk del .build-deps

# Copy php configs
COPY config/php/99-moodle.ini /usr/local/etc/php/conf.d/

COPY config/php/zzz-custom-pool.conf /usr/local/etc/php-fpm.d/

# ============================================
# Development Stage
# ============================================
FROM base AS development

RUN --mount=type=cache,target=/var/cache/apk \
    apk add --no-cache vim nano linux-headers \
    && apk add --no-cache --virtual .xdebug-deps autoconf g++ make \
    && pecl install xdebug-3.4.0 \
    && docker-php-ext-enable xdebug \
    && docker-php-ext-install pcntl \
    && apk del .xdebug-deps \
    && rm -rf /tmp/pear

# Set working directory
WORKDIR /var/www/html

# Dev: TIDAK copy src/ karena akan di-mount volume saat runtime
# Hanya buat struktur direktori yang dibutuhkan
RUN mkdir -p /var/www/html /var/www/moodledata \
    && chown -R www-data:www-data /var/www \
    && chmod 777 /var/www/moodledata

COPY --chmod=755 scripts/ /opt/scripts/
COPY --chmod=755 migration/ /opt/migration/
COPY --chmod=755 config/entrypoint/docker-entrypoint-dev.sh /entrypoint.sh

# HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=30s \
#     CMD php-fpm -t 2>/dev/null && test -f /var/www/html/index.php || exit 1

# ✅ FIX: healthcheck cek index.php di /public
HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=30s \
    CMD php-fpm -t 2>/dev/null && test -f /var/www/html/public/index.php || exit 1

ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
EXPOSE 9000

# Copy Moodle & backup untuk named volume
# COPY source moodle dari src/ .
# RUN mkdir -p /opt/moodle-source && cp -r /var/www/html/* /opt/moodle-source/
#COPY --chown=www-data:www-data src/ .

#RUN apk add --no-cache composer \
#    && composer install --no-interaction --no-dev --optimize-autoloader --ignore-platform-reqs \
#    && apk del composer
# Create moodledata directory
# RUN mkdir -p /var/www/moodledata \
#     && chown -R www-data:www-data /var/www \
#     && chmod -R 755 /var/www
#RUN mkdir -p /var/www/moodledata
# Copy Scripts
#COPY scripts/ /opt/scripts/
#COPY migration/ /opt/migration/
#RUN chmod +x /opt/scripts/*.sh

#COPY config/entrypoint/entrypoint.sh /entrypoint.sh
#RUN chmod +x /entrypoint.sh

# Health check
#HEALTHCHECK --interval=10s --timeout=5s --retries=3 \
#    CMD pidof php-fpm > /dev/null || exit 1

#ENV SERVICE_TYPE=php-fpm
#ENTRYPOINT ["/entrypoint.sh"]
#EXPOSE 9000

# ============================================
# Production Stage
# ============================================
FROM base AS production

# OPcache production - validate_timestamps=0 untuk performa
RUN { \
        echo "opcache.validate_timestamps=0"; \
        echo "opcache.revalidate_freq=0"; \
        echo "opcache.max_accelerated_files=20000"; \
        echo "display_errors=Off"; \
        echo "log_errors=On"; \
    } >> /usr/local/etc/php/conf.d/99-moodle.ini

# Optimize OPcache untuk production
# RUN echo "opcache.validate_timestamps=0" >> /usr/local/etc/php/conf.d/opcache.ini \
#     && echo "opcache.revalidate_freq=0" >> /usr/local/etc/php/conf.d/opcache.ini \
#     && echo "opcache.max_accelerated_files=10000" >> /usr/local/etc/php/conf.d/opcache.ini

# Set working directory
WORKDIR /var/www/html

# Copy Moodle & backup untuk named volume
# COPY moodle/ .
# RUN mkdir -p /opt/moodle-source && cp -r /var/www/html/* /opt/moodle-source/

COPY --chown=www-data:www-data --chmod=755 src/ .

RUN mkdir -p /var/www/moodledata \
    && chown -R www-data:www-data /var/www/moodledata \
    && chmod 777 /var/www/moodledata

COPY --chmod=755 scripts/ /opt/scripts/
COPY --chmod=755 migration/ /opt/migration/
COPY --chmod=755 config/entrypoint/docker-entrypoint-prod.sh /entrypoint.sh

# HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=60s \
#     CMD php-fpm -t 2>/dev/null && test -f /var/www/html/index.php || exit 1

# ✅ FIX: healthcheck cek index.php di /public
HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=60s \
    CMD php-fpm -t 2>/dev/null && test -f /var/www/html/public/index.php || exit 1


ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
EXPOSE 9000

# # Install composer dependencies
# RUN apk add --no-cache composer \
#     && composer install --no-interaction --no-dev --optimize-autoloader --ignore-platform-reqs \
#     && apk del composer

# # Create moodledata directory
# # RUN mkdir -p /var/www/moodledata \
# #     && chown -R www-data:www-data /var/www \
# #     && chmod -R 755 /var/www

# RUN mkdir -p /var/www/moodledata

# # Copy entrypoint
# COPY scripts/ /opt/scripts/
# COPY migration/ /opt/migration/
# RUN chmod +x /opt/scripts/*.sh

# COPY config/entrypoint/entrypoint.sh /entrypoint.sh
# RUN chmod +x /entrypoint.sh

# # Health check
# HEALTHCHECK --interval=10s --timeout=5s --retries=3 \
#     CMD pidof php-fpm > /dev/null || exit 1

# ENV SERVICE_TYPE=php-fpm
# ENTRYPOINT ["/entrypoint.sh"]
# EXPOSE 9000
