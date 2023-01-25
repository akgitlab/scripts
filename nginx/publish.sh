#!/bin/bash

# New resource publication on reverce-proxy server

# Andrey Kuznetsov, 2022.12.05
# Company: IT Service 5-55
# Telegram: https://t.me/akmsg

# The script is in the directory /usr/local/scripts/publish.sh
# For convenience create symbolic link ln -s /usr/local/scripts/publish.sh /usr/local/bin/publish
# And use like publish example.com


# Set logfile path
LOG="/var/log/nginx/publish.log"

# Get variables
EXTIP=$(curl eth0.me 2>&1)
USER=$(who | grep "/0" | head -n 1 | awk '{print($1)}')
FDQN=$1

# Make sure only root can run our script
if [[ $EUID -ne 0 ]]
then
  echo -e "\033[0m\033[0m\033[31mError: This script must be run only as root or privileged user!"
  tput sgr0
  exit 1
fi

# Start a new resource publish
echo -e "\n$(date '+%d/%m/%Y %H:%M:%S') [info] User $USER start a new resource publication" >> $LOG

# Check received user variables
if [[ $FDQN = "" ]]
then
  echo "$(date '+%d/%m/%Y %H:%M:%S') [warn] User did not enter the fully qualified domain name in the script launch options" >> $LOG
  echo -e "\033[0m\033[0m\033[33mWarning: Fully qualified domain name required!"
  tput sgr0
  exit 1
fi

# Check domain name DNS entry
echo "Domain DNS entry existence check by using DIG service..."
dig $FDQN +noall +answer | grep "$EXTIP" > /dev/null 2>&1
if [ $? -eq 1 ]
then
  echo "$(date '+%d/%m/%Y %H:%M:%S') [error] External IP address does not match the DNS entry or the entry is missing" >> $LOG
  echo -e "\033[0m\033[0m\033[31mError: Current external IP address does not match the DNS entry or the entry is missing!"
  tput sgr0
  exit 1
else
  echo -e "\033[32mSuccess: DNS entry found for this domain. Continue..."
  tput sgr0
fi

# Configuration file existence check
echo "Resource configuration file existence check..."
sleep 2
if [ -f /etc/nginx/sites-available/$FDQN ]
then
  echo "$(date '+%d/%m/%Y %H:%M:%S') [warn] The configuration file for $FDQN already exists" >> $LOG
  echo -e "\033[0m\033[0m\033[33mWarning: The configuration file for this resource already exists!"
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
  echo "$(date '+%d/%m/%Y %H:%M:%S') [error] Destination server is not available" >> $LOG
  echo -e "\033[0m\033[0m\033[31mError: Destination server is not available, check it before next script run!"
  tput sgr0
  exit 1
else

# Get received user variables
read -r -p "Enter the name of the fullchain certificate file (for example: star.5-55.ru.chained.pem): " CRT

# Certificate existence check
if [ ! -f /home/$USER/$CRT ] && [ ! -f /etc/nginx/certs/$CRT ]
then
  echo "$(date '+%d/%m/%Y %H:%M:%S') [error] Certificate file not found" >> $LOG
  echo -e "\033[0m\033[0m\033[31mError: Certificate file not found in directory /home/$USER/ or /etc/nginx/certs/ !"
  tput sgr0
  exit 1
else

# Get received user variables
read -r -p "Enter the name of the private key file (for example: star.5-55.ru.key): " KEY

# Key file existence check
if [ ! -f /home/$USER/$KEY ] && [ ! -f /etc/nginx/certs/$KEY ]
then
  echo "$(date '+%d/%m/%Y %H:%M:%S') [error] Private key file not found" >> $LOG
  echo -e "\033[0m\033[0m\033[31mError: Private key file not found in directory /home/$USER/ or /etc/nginx/certs/ !"
  tput sgr0
  exit 1
else
  mv -n /home/$USER/$CRT /etc/nginx/certs/ > /dev/null 2>&1
  mv -n /home/$USER/$KEY /etc/nginx/certs/ > /dev/null 2>&1

# Checksum verification
CMD5=$(openssl x509 -noout -modulus -in /etc/nginx/certs/$CRT | md5sum)
KMD5=$(openssl rsa -noout -modulus -in /etc/nginx/certs/$KEY | md5sum)
if [ "$CMD5" != "$KMD5" ]
then
  echo "$(date '+%d/%m/%Y %H:%M:%S') [error] The checksums of the certificate and private key do not match" >> $LOG
  echo -e "\033[0m\033[0m\033[31mError: The checksums of the certificate and private key do not match!"
  tput sgr0
  exit 1
else
  echo -e "\033[32mSuccess: The checksums of the certificate and the private key matched. Continue..."
  tput sgr0
fi

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
    ssl_certificate /etc/nginx/certs/$CRT;
    ssl_certificate_key /etc/nginx/certs/$KEY;

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
read -r -p "Do you really want to write configuration file and activate the resource now? [y/n] " response
if ! [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]
then
  rm /etc/nginx/sites-available/"$FDQN"
  echo "$(date '+%d/%m/%Y %H:%M:%S') [warn] Resource publish setup aborted by user" >> $LOG
  echo -e "\033[0m\033[0m\033[33mWarning: Resource publish setup aborted by user"
  tput sgr0
  exit 1
else

# Final stage of action
echo "Making symbolic link..."
ln -s /etc/nginx/sites-available/"$FDQN" /etc/nginx/sites-enabled/"$FDQN"
echo "Soft reload NGING proxy service..."
nginx -t >> $LOG  2>&1
/etc/init.d/nginx reload > /dev/null 2>&1

if [ $? -eq 0 ]
then
  echo -e "\033[32mSuccess: Service Nginx restart completed and new site has been setup. Continue..."
  tput sgr0
else
  rm /etc/nginx/sites-available/"$FDQN"
  rm /etc/nginx/sites-enabled/"$FDQN"
  /etc/init.d/nginx reload > /dev/null 2>&1
  echo "$(date '+%d/%m/%Y %H:%M:%S') [error] Certificate or key error encountered while checking configuration file" >> $LOG
  echo -e "\033[0m\033[0m\033[31mError: Check the existence and names of the certificates and try again later!"
  tput sgr0
  exit 1
fi
fi
fi

# Сhecking the published resource
echo "Get the published resource status code..."
curl -Is https://$FDQN | head -1 | grep "200" > /dev/null 2>&1
if [ $? -eq 1 ]
then
  echo "$(date '+%d/%m/%Y %H:%M:%S') [error] Published resource does not give status code 200" >> $LOG
  echo -e "\033[0m\033[0m\033[31mError: Published resource does not give status code 200! Please check the configuration file use nano /etc/nginx/sites-available/$FDQN"
  tput sgr0
  exit 1
else
  echo "$(date '+%d/%m/%Y %H:%M:%S') [info] New resource $FDQN already published and gave status code 200" >> $LOG
  echo -e "\033[32mSuccess: New resource already published and gave status code 200. Enjoy now!"
  tput sgr0
fi
