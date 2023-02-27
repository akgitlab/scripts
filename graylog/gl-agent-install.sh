#!/bin/bash

# Install Graylog script for debian server
# Andrey Kuznetsov, 2023.02.27
# Telegram: https://t.me/akmsg


# Install Graylog sidecar
cd /tmp
wget https://packages.graylog2.org/repo/packages/graylog-sidecar-repository_1-5_all.deb
dpkg -i graylog-sidecar-repository_1-5_all.deb
apt update && apt install graylog-sidecar
curl https://raw.githubusercontent.com/akgitlab/files/main/graylog/sidecar/linux/debian/config/sidecar.yml > /etc/graylog/sidecar/sidecar.yml
graylog-sidecar -service install
systemctl enable graylog-sidecar && systemctl start graylog-sidecar

# Install Filebeat
cd /tmp
wget https://github.com/akgitlab/files/releases/download/filebeat/filebeat-8.6.2-amd64.deb
dpkg -i filebeat-8.6.2-amd64.deb
apt install filebeat
systemctl enable filebeat && systemctl start filebeat
