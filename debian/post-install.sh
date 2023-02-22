#!/bin/bash

# After install script for debian server
# Andrey Kuznetsov, 2023.02.21
# Telegram: https://t.me/akmsg

# WARNING! Carefully check all the settings, because by applying this script you can block your access to the server!


# Set messages colors
RESET='\033[0m'
YELLOW='\033[1;33m'
GRAY='\033[0;37m'
WHITE='\033[1;37m'
GRAY_R='\033[39m'
WHITE_R='\033[39m'
RED='\e[31m'
GREEN='\e[32m'

# Set logfile path
LOG="/var/log/post-install.log"

# Get variables

# Print script logo
script_logo() {
  cat << "EOF"
________             _____       _____              _____       ___________
___  __ \______________  /_      ___(_)_______________  /______ ___  /__  /
__  /_/ /  __ \_  ___/  __/________  /__  __ \_  ___/  __/  __ `/_  /__  / 
_  ____// /_/ /(__  )/ /_ _/_____/  / _  / / /(__  )/ /_ / /_/ /_  / _  /  
/_/     \____//____/ \__/        /_/  /_/ /_//____/ \__/ \__,_/ /_/  /_/   
EOF
}

start_script() {
  script_logo
  echo -e "Script for easy new packages instalation by AK"
  sleep 3
}
start_script


# Make sure only root can run our script
if [[ $EUID -ne 0 ]]
then
  echo -e "\033[0m\033[0m\033[31mError: This script must be run only as root or privileged user!"
  tput sgr0
  exit 1
fi

# Start a post-install script
echo -e "\n$(date '+%d/%m/%Y %H:%M:%S') [info] User $USER start a post-install script" >> $LOG

# Set current timezone
timedatectl set-timezone Europe/Moscow


# Repository





apt update && apt -y upgrade

apt -y install sudo mc htop screen screenfetch ncdu gnupg curl wget



# Install and minimal configuration zabbix-agent
if [ -x /usr/bin/apt-get ]; then
  cd /tmp
  wget https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_6.0-4%2Bdebian11_all.deb
  dpkg -i zabbix-release_6.0-4+debian11_all.deb
  apt update
  apt-get -y install zabbix-agent
  sed -i 's/Server=127.0.0.1/Server=10.0.22.21/' /etc/zabbix/zabbix_agentd.conf
  systemctl restart zabbix-agent
  systemctl enable zabbix-agent
fi



sudo apt -y autoremove
sudo apt -y clean

https://github.com/ahmetcancicek/debian-post-install/blob/main/install-sudo.sh
