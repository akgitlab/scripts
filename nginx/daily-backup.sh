#!/bin/bash

# Daily backup of nginx configuration files

# Andrey Kuznetsov, 2022.12.04
# Company: IT Service 5-55
# Telegram: https://t.me/akmsg

if ! [ -d /var/backups/nginx/daily ]
then
  mkdir -p /var/backups/nginx/daily
fi
cd /etc/nginx
tar -czf /var/backups/nginx/daily/backup_$(date +'%F_%H-%M-%S').tar.gz ./
find /var/backups/nginx/daily/backup* -mtime +30 -exec rm {} \;
exit 0
