
ARG ENVIRONMENT=production

FROM php:8.4-fpm-alpine AS base

# Install runtime dependencies (jarang berubah - di-cache)
RUN --mount=type=cache,target=/var/cache/apk \
    apk add --no-cache \
    unzip \
    gettext \
    libzip \
    libpng \
    libjpeg \
    postgresql-client \
    icu-libs \
    libxml2 \
    curl \
    wget \
    git \
    bash

# Install PHP extensions (jarang berubah - di-cache)
RUN --mount=type=cache,target=/var/cache/apk \
    apk add --no-cache --virtual .build-deps \
    libzip-dev \
    libpng-dev \
    libjpeg-turbo-dev \
    libpq-dev \
    icu-dev \
    libxml2-dev \
    && docker-php-ext-configure gd --with-jpeg \
    && docker-php-ext-configure zip \
    && docker-php-ext-install \
        zip \
        gd \
        pdo_pgsql \
        pgsql \
        intl \
        soap \
        exif \
    && apk del .build-deps

# Copy php configs
COPY php/99-moodle.ini /usr/local/etc/php/conf.d/

# ============================================
# Development Stage
# ============================================
FROM base AS development

RUN --mount=type=cache,target=/var/cache/apk \
    apk add --no-cache vim nano linux-headers \
    && apk add --no-cache --virtual .xdebug-deps autoconf g++ make \
    && pecl install xdebug \
    && docker-php-ext-enable xdebug \
    && docker-php-ext-install pcntl \
    && apk del .xdebug-deps \
    && rm -rf /tmp/pear

# Set working directory
WORKDIR /var/www/html

# Copy Moodle & backup untuk named volume
COPY moodle/ .
RUN mkdir -p /opt/moodle-source && cp -r /var/www/html/* /opt/moodle-source/

# Create moodledata directory
RUN mkdir -p /var/www/moodledata \
    && chown -R www-data:www-data /var/www \
    && chmod -R 755 /var/www

# Copy entrypoint
COPY moodle/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Health check
HEALTHCHECK --interval=10s --timeout=5s --retries=3 \
    CMD pidof php-fpm > /dev/null || exit 1

ENV SERVICE_TYPE=php-fpm
ENTRYPOINT ["/entrypoint.sh"]
EXPOSE 9000

# ============================================
# Production Stage
# ============================================
FROM base AS production

# Optimize OPcache untuk production
RUN echo "opcache.validate_timestamps=0" >> /usr/local/etc/php/conf.d/opcache.ini \
    && echo "opcache.revalidate_freq=0" >> /usr/local/etc/php/conf.d/opcache.ini \
    && echo "opcache.max_accelerated_files=10000" >> /usr/local/etc/php/conf.d/opcache.ini

# Set working directory
WORKDIR /var/www/html

# Copy Moodle & backup untuk named volume
COPY moodle/ .
RUN mkdir -p /opt/moodle-source && cp -r /var/www/html/* /opt/moodle-source/

# Create moodledata directory
RUN mkdir -p /var/www/moodledata \
    && chown -R www-data:www-data /var/www \
    && chmod -R 755 /var/www

# Copy entrypoint
COPY moodle/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Health check
HEALTHCHECK --interval=10s --timeout=5s --retries=3 \
    CMD pidof php-fpm > /dev/null || exit 1

ENV SERVICE_TYPE=php-fpm
ENTRYPOINT ["/entrypoint.sh"]
EXPOSE 9000