#!/bin/bash

# Adding a new resource to reverce-proxy server
# Andrey Kuznetsov, 2022.10.26
# Telegram: https://t.me/akmsg

# Get variables
FDQN=$1
SRV=$2
CRT=$3
KEY=$4
DATE=$(date  +%Y)

# Start creating configuration file for new site
echo "Making configuration file for  $FDQN..."
(
cat <<EOF
server {
    listen 80;
    server_name $FDQN;
    return 301 https://$FDQN$request_uri;
}

server {
    listen 443 ssl;
    server_name $FDQN;

    # SSL certificate files
    ssl_certificate /etc/nginx/certs/$DATE/$CRT;
    ssl_certificate_key /etc/nginx/certs/$DATE/$KEY;

    # Log files
    access_log /var/log/nginx/$FDQN.access.log;
    error_log /var/log/nginx/$FDQN.error.log;

    # Content encoding
    charset utf-8;

    # Proxy redirect
    location / {
      proxy_pass http://$SRV;
      include /etc/nginx/proxy_params;
    }

    # Redirect 403 errors to 404 error to fool attackers
    error_page 403 = 404;
}
EOF
) >  /etc/nginx/sites-available/$FDQN

echo "Making symbolic link for $FDQN and reload service..."
ln -s /etc/nginx/sites-available/"$FDQN" /etc/nginx/sites-enabled/"$FDQN"
/etc/init.d/nginx reload
echo "Service Nginx restart completed. $FDQN has been setup. Enjoy!"
