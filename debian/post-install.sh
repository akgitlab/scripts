#!/bin/bash

# Post-install script for Debian server
# Andrey Kuznetsov, 2024.10.29
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

# Real username
RUSER=$(who | awk '{print $1}')

# IP address of new host
IP=$(hostname -I)

# Old hostname
OLDNAME=$(hostname)

# Path for executable
PATH=$PATH:/sbin


# Clearing the screen from previously entered commands
clear -x

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
  sleep 5
}
start_script

# User privilege check
if [[ $EUID -ne 0 ]]
then
  echo -e "\033[0m\033[0m\033[31mError: This script must be run only as root or privileged user!"
  echo -e ""
  tput sgr0
  exit 1
fi

# Get received user variables
read -r -p "Enter a name for the server to be deployed (for example: ansible.5-55.ru): " FDQN
hostnamectl set-hostname $FDQN
sed -i -e "s/$OLDNAME/$FDQN/g" /etc/hosts

# Start a post-install script
echo -e "\n$(date '+%d/%m/%Y %H:%M:%S') [info] User $USER start a post-install script" >> $LOG

# Set current timezone
timedatectl set-timezone Europe/Moscow

# Add DNS servers
(
cat <<EOF
# Post install script generated
search 5-55.ru
nameserver 192.168.22.2
nameserver 192.168.44.2
EOF
) >  /etc/resolv.conf

# Disable IPv6 protocol
(
cat <<EOF
net.ipv6.conf.all.disable_ipv6 = 1
EOF
) >  /etc/sysctl.d/90-disable-ipv6.conf

# Add standart debian 12 repository
(
cat <<EOF
# Official sources for Debian GNU/Linux 12.0.0 Bookworm

deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware

deb http://deb.debian.org/debian-security/ bookworm-security main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian-security/ bookworm-security main contrib non-free non-free-firmware

deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
EOF
) >  /etc/apt/sources.list

# Update system packages
apt update && apt -y upgrade

# Install minimal required pfckages
apt -y install sudo mc htop screen screenfetch ncdu gnupg curl wget net-tools parted rsyslog

# Install build-essential (uncomment if necessary)
#apt -y install build-essential dkms linux-headers-$(uname -r)

# Install and minimal configuration zabbix-agent
if [ -x /usr/bin/apt-get ]; then
  cd /tmp
  wget https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_6.0-5+debian12_all.deb
  dpkg -i zabbix-release_6.0-5+debian12_all.deb
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

# User setup
/sbin/usermod -aG sudo $RUSER
echo "$RUSER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$RUSER
echo -en "\n# Set the TERM for xterm in the xterm configuration and that for tmux configuration\nexport TERM=xterm-256color" >> /root/.profile
echo -en "\n# Set the TERM for xterm in the xterm configuration and that for tmux configuration\nexport TERM=xterm-256color" >> /home/$RUSER/.profile
mkdir -p /root/.config/mc
curl https://raw.githubusercontent.com/akgitlab/files/main/config/mc/root/ini > /root/.config/mc/ini
curl https://raw.githubusercontent.com/akgitlab/files/main/config/mc/root/panels.ini > /root/.config/mc/panels.ini
mkdir -p /home/$RUSER/.config/mc
curl https://raw.githubusercontent.com/akgitlab/files/main/config/mc/users/ini > /home/$RUSER/.config/mc/ini
curl https://raw.githubusercontent.com/akgitlab/files/main/config/mc/users/panels.ini > /home/$RUSER/.config/mc/panels.ini
chown -R $RUSER:$RUSER /home/$RUSER/.config
sed -i -e "s/devops/$RUSER/g" /home/$RUSER/.config/mc/panels.ini
echo -e "\n# User specific aliases and functions\nexport EDITOR=/bin/nano" >> /root/.bashrc
echo -e "\n# User specific aliases and functions\nexport EDITOR=/bin/nano" >> /home/$RUSER/.bashrc

# Change motd banner on users logon
echo -n > /etc/motd
rm -rf /etc/update-motd.d/*
curl https://raw.githubusercontent.com/akgitlab/scripts/main/debian/00-info.sh > /etc/update-motd.d/00-info
chmod +x /etc/update-motd.d/00-info
curl https://raw.githubusercontent.com/akgitlab/scripts/main/debian/00-msg > /etc/update-motd.d/00-msg

# Secure shell change config
sed -i 's/^#Port .*/Port 22/' /etc/ssh/sshd_config
sed -i 's/^#AddressFamily .*/AddressFamily inet/' /etc/ssh/sshd_config
sed -i 's/^#PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#PrintLastLog .*/PrintLastLog no/' /etc/ssh/sshd_config

# Enable user audit
curl https://raw.githubusercontent.com/akgitlab/scripts/main/debian/user-audit.sh >> /etc/bash.bashrc
mkdir /var/log/bash
echo "local7.* /var/log/bash/user-audit.log" > /etc/rsyslog.d/user-audit.conf

# Finish actions
rm /home/$RUSER/post-install.sh
apt -y autoremove && apt -y clean
reboot
