#!/bin/sh

# Substitute environment variables in nginx config template
envsubst '${ACTIVE_POOL}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# Test configuration
nginx -t

# Start nginx in foreground
nginx -g "daemon off;"