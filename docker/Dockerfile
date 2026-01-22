FROM php:8.1-apache

# Install dependency OS + PHP extensions yang dibutuhkan Moodle
RUN apt-get update && apt-get install -y \
    git unzip libzip-dev libpng-dev libjpeg-dev libfreetype6-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install mysqli zip gd \
    && rm -rf /var/lib/apt/lists/*

# Enable Apache rewrite (wajib untuk Moodle)
RUN a2enmod rewrite

# Set working directory Apache
WORKDIR /var/www/html

# Clone Moodle stable branch
RUN git clone -b MOODLE_401_STABLE https://github.com/moodle/moodle.git .

# Buat moodledata (di luar web root)
RUN mkdir /var/www/moodledata \
 && chown -R www-data:www-data /var/www/html /var/www/moodledata
