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


# Add DNS servers
(
cat <<EOF
# Post install script generated
search 5-55.ru
nameserver 10.1.1.10
nameserver 10.216.55.230
EOF
) >  /etc/resolv.conf

# Disable IPv6 protocol
(
cat <<EOF
net.ipv6.conf.all.disable_ipv6 = 1
EOF
) >  /etc/sysctl.d/90-disable-ipv6.conf


# Add standart debian repository
(
cat <<EOF
# Official sources for Debian GNU/Linux 11.0.0 Bullseye

deb http://deb.debian.org/debian/ bullseye main
deb-src http://deb.debian.org/debian/ bullseye main

deb http://security.debian.org/debian-security bullseye-security main contrib
deb-src http://security.debian.org/debian-security bullseye-security main contrib

deb http://deb.debian.org/debian/ bullseye-updates main contrib
deb-src http://deb.debian.org/debian/ bullseye-updates main contrib
EOF
) >  /etc/apt/sources.list


# Update system packages
apt update && apt -y upgrade


# Install minimal required pfckages
apt -y install sudo mc htop screen screenfetch ncdu gnupg curl wget


# Install and minimal configuration zabbix-agent
if [ -x /usr/bin/apt-get ]; then
  cd /tmp
  wget https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_6.0-4%2Bdebian11_all.deb
  dpkg -i zabbix-release_6.0-4+debian11_all.deb
  apt update
  apt-get -y install zabbix-agent
  sed -i 's/Server=127.0.0.1/Server=10.0.22.21/' /etc/zabbix/zabbix_agentd.conf
  sed -i '/### Option: LogRemoteCommands/i AllowKey=system.run[*]' /etc/zabbix/zabbix_agentd.conf
  sed -i '/### Option: LogRemoteCommands/{x;p;x;}' /etc/zabbix/zabbix_agentd.conf
  sed -i '/# ListenIP=0.0.0.0/a ListenIP=0.0.0.0' /etc/zabbix/zabbix_agentd.conf
  sed -i '/# ListenIP=0.0.0.0/G' /etc/zabbix/zabbix_agentd.conf
  sed -i '/# Timeout=3/a Timeout=30' /etc/zabbix/zabbix_agentd.conf
  sed -i '/# Timeout=3/G' /etc/zabbix/zabbix_agentd.conf
  sed -i '/# UnsafeUserParameters=0/a UnsafeUserParameters=1' /etc/zabbix/zabbix_agentd.conf
  sed -i '/# UnsafeUserParameters=0/G' /etc/zabbix/zabbix_agentd.conf
  systemctl restart zabbix-agent
  systemctl enable zabbix-agent
fi


# User setup
/sbin/usermod -aG sudo devops
echo "devops ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/devops
echo -en "\n# Set the TERM for xterm in the xterm configuration and that for tmux configuration\nexport TERM=xterm-256color" >> /root/.profile
echo -en "\n# Set the TERM for xterm in the xterm configuration and that for tmux configuration\nexport TERM=xterm-256color" >> /home/devops/.profile


# Change motd banner on users logon
echo -e > /etc/motd
rm -rf /etc/update-motd.d/*

(
cat <<EOF
#!/usr/bin/env bash

# OS available?
if [ -f /etc/os-release ]; then
    source /etc/os-release
else
    PRETTY_NAME="Linux"
fi

# Welcome message
cat /etc/update-motd.d/00-msg
printf "\n%s\n" "$(date)"
printf "Distro: %s | Core: %s\n" "$PRETTY_NAME" "$(uname -r)"
echo "Powered by Debian is a distribution of Free Software and maintained and updated through the work of many users who volunteer..."
echo ""

# Show failed services
systemctl list-units --state failed --type service | awk 'FNR>1' | grep failed
echo ""
EOF
) >  /etc/update-motd.d/00-info

chmod +x /etc/update-motd.d/00-info

(
cat <<EOF
              ,,                                                                                               
  .g8"""bgd `7MM                                                              mm                               
.dP'     `M   MM                                                              MM                               
dM'       `   MM   .gP"Ya   ,6"Yb.  `7Mb,od8     ,pP"Ybd `7M'   `MF',pP"Ybd mmMMmm   .gP"Ya  `7MMpMMMb.pMMMb.  
MM            MM  ,M'   Yb 8)   MM    MM' "'     8I   `"   VA   ,V  8I   `"   MM    ,M'   Yb   MM    MM    MM  
MM.           MM  8M""""""  ,pm9MM    MM         `YMMMa.    VA ,V   `YMMMa.   MM    8M""""""   MM    MM    MM  
`Mb.     ,'   MM  YM.    , 8M   MM    MM         L.   I8     VVV    L.   I8   MM    YM.    ,   MM    MM    MM  
  `"bmmmd'  .JMML. `Mbmmd' `Moo9^Yo..JMML.       M9mmmP'     ,V     M9mmmP'   `Mbmo  `Mbmmd' .JMML  JMML  JMML.
                                                            ,V                                                 
                                                         OOb"                                                  
Welcome to new system based of Debian!

Attention user! Your actions can have irreversible consequences.
This server is running in a production environment. Use a different server for testing!

EOF
) >  /etc/update-motd.d/00-msg


# Secure shell change config
sed -i 's/^#Port .*/Port 22/' /etc/ssh/sshd_config
sed -i 's/^#ListenAddress .*/ListenAddress 0.0.0.0/' /etc/ssh/sshd_config
sed -i 's/^#PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#PrintLastLog .*/PrintLastLog no/' /etc/ssh/sshd_config


# Finish actions
apt -y autoremove
apt -y clean
sudo reboot
