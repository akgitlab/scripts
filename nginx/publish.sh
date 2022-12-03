#!/bin/bash

# Adding a new resource to reverce-proxy server

# Andrey Kuznetsov, 2022.10.26
# Company: IT Service 5-55
# Telegram: https://t.me/akmsg

# Get variables
DATE=$(date  +%Y)
EXTIP=$(curl eth0.me 2>&1)
FDQN=$1

# Make sure only root can run our script
if [[ $EUID -ne 0 ]]
then
  echo -e "\033[0m\033[0m\033[31mError: This script must be run as root!"
  tput sgr0
  exit 1
fi

# Check received user variables
if [[ $FDQN = "" ]]
then
  echo -e "\033[0m\033[0m\033[31mError: Fully qualified domain name required!"
  tput sgr0
  exit 1
fi

# Check for domain name availability
echo "Domain DNS records existence check by using DIG service..."
dig $FDQN +noall +answer | grep "$EXTIP" > /dev/null 2>&1
if [ $? -eq 1 ]
then
  echo -e "\033[0m\033[0m\033[31mError: Current external IP address does not match the DNS entry or the entry is missing!"
  tput sgr0
  exit 1
else
  echo -e "\033[32mSuccess: DNS records found for this domain. Continue..."
  tput sgr0
fi

# Configuration file existence check
echo "Configuration file existence check..."
sleep 2
if [ -f /etc/nginx/sites-available/$FDQN ]
then
  echo -e "\033[0m\033[0m\033[31mError: The configuration for this resource already exists!"
  tput sgr0
  exit 1
else

# Get received user variables
read -r -p "Enter the IP address of the server on the internal network: " SRV

# Start destination server ping check
echo "Destination server ping check..."
ping -c 3 $SRV  2>&1 > /dev/null
if [ $? -ne 0 ]
then
  echo -e "\033[0m\033[0m\033[31mError: Destination server is not available, check it before next script run!"
  tput sgr0
  exit 1
else

# Get received user variables
read -r -p "Enter the name of the fullchain certificate file (for example: star.5-55.ru.bundle.pem): " CRT

# Certificate existence check
if [ ! -f /etc/nginx/certs/$DATE/$CRT ]
then
  echo -e "\033[0m\033[0m\033[31mError: Certificate file not found in directory /etc/nginx/certs/$DATE/ !"
  tput sgr0
  exit 1
else

# Get received user variables
read -r -p "Enter the name of the private key file (for example: star.5-55.ru.key): " KEY

# Key file existence check
if [ ! -f /etc/nginx/certs/$DATE/$KEY ]
then
  echo -e "\033[0m\033[0m\033[31mError: Key file not found in directory /etc/nginx/certs/$DATE/ !"
  tput sgr0
  exit 1
else

# Start creating configuration file for new site
echo "Making configuration file..."
(
cat <<EOF
server {
    listen 80;
    server_name $FDQN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $FDQN;

    # SSL certificate files
    ssl_certificate /etc/nginx/certs/$DATE/$CRT;
    ssl_certificate_key /etc/nginx/certs/$DATE/$KEY;

    # Log files path
    access_log /var/log/nginx/$FDQN.access.log;
    error_log /var/log/nginx/$FDQN.error.log warn;

    # Content encoding
    charset utf-8;

    # Proxy redirect
    location / {
      proxy_pass https://$SRV;
      include /etc/nginx/proxy_params;
    }

    # Redirect 403 errors to 404 error to fool attackers
    error_page 403 = 404;
}
EOF
) >  /etc/nginx/sites-available/$FDQN
fi
fi
fi

# User confirmation request
read -r -p "Do you really want to create a config file and activate the resource now? [y/n] " response
if ! [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]
then
  rm /etc/nginx/sites-available/"$FDQN"
  echo -e "\033[0m\033[0m\033[31mError: Resource publish setup aborted by user!"
  tput sgr0
  exit 1
else

# Final stage of action
echo "Making symbolic link..."
ln -s /etc/nginx/sites-available/"$FDQN" /etc/nginx/sites-enabled/"$FDQN"
echo "Reload NGING proxy service..."
nginx -t > /var/log/nginx/reload.log 2>&1
/etc/init.d/nginx reload > /dev/null 2>&1

if [ $? -eq 0 ]
then
  echo -e "\033[32mSuccess: Service Nginx restart completed and new site has been setup!"
  tput sgr0
else
  rm /etc/nginx/sites-available/"$FDQN"
  rm /etc/nginx/sites-enabled/"$FDQN"
  /etc/init.d/nginx reload > /dev/null 2>&1
  echo -e "\033[0m\033[0m\033[31mError: Check the existence and names of the certificates and try again later..."
  tput sgr0
fi
fi
fi
