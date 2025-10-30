FROM nginx:1.23-alpine

# Install envsubst and curl for health checks
RUN apk add --no-cache gettext curl

# Copy template and startup script
COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY start-nginx.sh /start-nginx.sh

RUN chmod +x /start-nginx.sh

CMD ["/start-nginx.sh"]
EXPOSE 8080