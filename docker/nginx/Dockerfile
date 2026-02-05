FROM nginx:alpine

# COpy Nginx config file
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/moodle.conf /etc/nginx/conf.d/default.conf

# Create cache directory

RUN mkdir -p /var/cache/nginx && chown -R nginx:nginx /var/cache/nginx

# Health check
HEALTHCHECK --interval=10s --timeout=5s  --retries=3 \
     CMD wget --no-verbose --tries=1 --spider http://localhost/health || exit 1


# Expose ports

EXPOSE 80 443
