#!/bin/bash

# System audit script
# Andrey Kuznetsov, 2025.02.05
# Telegram: https://t.me/akmsg

# This is a system audit bash script to gather instantly information about your Linux system
# which can also help you in the process of hardening.

# Version
VERSION="v1.0 beta"

# Set messages colors
RESET='\033[0m'
YELLOW='\033[1;33m'
GRAY='\033[0;37m'
WHITE='\033[1;37m'
GRAY_R='\033[39m'
WHITE_R='\033[39m'
RED='\e[31m'
GREEN='\e[32m'

# Hostname
RNAME=$(hostname | tr [:lower:] [:upper:])
FILENAME=$(hostname)

# Real username
RUSER=$(who | awk '{print $1}' | head -1)

# Set report file path
WORKFILE="/tmp/system-audit.sh"
RAWDATA="/tmp/$FILENAME-audit.raw"
REPORT="/tmp/$FILENAME-audit.txt"
ARCHIVE="/tmp/$FILENAME-audit.tar.gz"
WEBDAV="https://work.sharegate.ru/audit/$FILENAME-audit.tar.gz"

# For timer to script
START=$(date +%s)

# Clearing the screen and oldfile from previously entered commands
clear -x
rm -f $REPORT

# Installing required packages
apt-get -y install curl &> /dev/null

# Print script logo
script_logo() {
  cat << "EOF"
________                 _____                   _______         ______________ _____ 
__  ___/_____  ____________  /______ _______ ___ ___    |____  ________  /___(_)__  /_
_____ \ __  / / /__  ___/_  __/_  _ \__  __ `__ \__  /| |_  / / /_  __  / __  / _  __/
____/ / _  /_/ / _(__  ) / /_  /  __/_  / / / / /_  ___ |/ /_/ / / /_/ /  _  /  / /_  
/____/  _\__, /  /____/  \__/  \___/ /_/ /_/ /_/ /_/  |_|\__,_/  \__,_/   /_/   \__/  
        /____/                                                                        

EOF
}

start_script() {
  script_logo
  echo -e "Welcome to system audit of your Linux system!"
  echo
  echo "Script will automatically gather the required info."
  echo "The checklist can help you in the process of hardening your system."
  echo "It has been tested for Debian Linux Distro."
}
start_script

sleep 1

# User privilege check
if [[ $EUID -ne 0 ]]; then
  echo -e "\033[0m\033[0m\033[31mError: This script must be run only as root or privileged user!"
  echo -e ""
  tput sgr0
  exit 1
fi

# Request to save results
echo
while true; do
  read -p "Would you like save the output to file? [Y/N] " output
  case "${output^^}" in
    Y)
      echo "You are required to enter the data previously provided to you access to WebDAV"
      echo
      read -p "Enter your login: " username
      read -s -p "Enter your password: " password
      echo
      echo
      echo "Result will be saved to $WEBDAV"
      echo "The link will be active for 1 hour!"
      break
      ;;
    N)
      echo "Result will not be saved, moving on."
      break
      ;;
    *)
      echo -e "\033[0m\033[0m\033[31mError: Incorrect value entered."
      echo -e ""
      tput sgr0
      ;;
  esac
done

echo
echo "So, let's begin..."
echo "Script started at $(date '+%d/%m/%Y %H:%M:%S')"
echo "Please wait to finish system audit for $RNAME"
sleep 1
echo

# Function to perform audit
perform_audit() {

echo
echo -e "\e[0;33m##### 1. Hardware information #####\e[0m"
  hostnamectl | sed -e 's/^[^[:alpha:]]\+//' | grep -vE "(Icon|hostname|Kernel|Operating|Firmware|ID)" | sort -n
  lscpu | grep -E 'Vendor|Model name|Core|Virtualization' | grep -vE "(BIOS Model name|Vendor ID)" | sed -e "s/[[:space:]]\+/ /g"
  out=$(awk '/MemTotal/ {printf "%.2f GB\n", $2/1024/1024}' /proc/meminfo)
  echo "Available memory: $out"
echo

echo -e "\e[0;33m##### 2. Block devices information #####\e[0m"
  lsblk
echo

echo -e "\e[0;33m##### 3. Mounted network resources #####\e[0m"
  out=$(mount | grep -E 'type (nfs|cifs|smb|nfs4)' | sed 's/(.*//')
  mntcount=$(mount | grep -E 'type (nfs|cifs|smb|nfs4)' | sed 's/(.*//' | wc -l)
    if [ -z "$out" ]; then
      echo "No mounted resources found"
    else
      echo "Mount points: $mntcount"
      echo "$out"
    fi
echo

echo -e "\e[0;33m##### 4. Kernel information #####\e[0m"
  cat /proc/sys/kernel/{osrelease,version} | tr -d '#' | sort -n
  out=$(dmesg -H | grep -i "error" | sed 's/^[^a-zA-Z]*//' | uniq 2>/dev/null)
  errorcount=$(dmesg -H | grep -i "error" | sed 's/^[^a-zA-Z]*//' | uniq | wc -l 2>/dev/null)
    if [ -z "$out" ]; then
      echo "No kernel errors found"
    else
      echo "Kernel errors found: $errorcount"
      echo "$out"
    fi
echo

echo -e "\e[0;33m##### 5. System runtime information #####\e[0m"
  out=$(uptime -p | cut -d " " -f2-)
    if [ -z "$out" ]; then
      echo "No information about uptime"
    else
      echo "Uptime: $out"
      echo "Boot at: $(who -b | awk '{print $3, $4}' | xargs -I {} date -d "{}" +"%d/%m/%Y %H:%M:%S")"
    fi
echo

echo -e "\e[0;33m##### 6. Distribution information #####\e[0m"
  lsb_release -a 2>/dev/null | sed -e "s/[[:space:]]\+/ /g"
  echo "Installed at: $(ls -lct --time-style=+"%d/%m/%Y %H:%M:%S" / | tail -1 | awk '{print $6, $7}')"
  echo "Last updated at: $(date -d @"$(stat -c %Y /var/cache/apt/)" +"%d/%m/%Y %H:%M:%S")"
echo

echo -e "\e[0;33m##### 7. Checks packages broken dependencies #####\e[0m"
  apt-get check
echo

echo -e "\e[0;33m##### 8. Network interfaces addresses #####\e[0m"
  intip=$(ip a | grep -E 'inet ' | awk '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//' | grep -vE "(127.0.0.1)")
    echo "Internal: $intip"
  out=$(curl -s eth0.me)
    if [ -z "$out" ]; then
      echo "External: no external IP info"
    else
      echo "External: $out/32"
    fi
echo

echo -e "\e[0;33m##### 9. Routing table #####\e[0m"
  ip route
echo

echo -e "\e[0;33m##### 10. Firewall and fail2ban availability #####\e[0m"
  if command -v iptables >/dev/null 2>&1; then
    out=$(systemctl status iptables | grep "Active:" | sed -e 's/^[^[:alpha:]]\+//') | awk -F': ' '{print $2}'
    echo "Iptables status: $out"
  else
    echo "Iptables status: not found"
  fi

  if systemctl is-active --quiet firewalld; then
    out=$(systemctl status firewalld | grep "Active:" | sed -e 's/^[^[:alpha:]]\+//' | awk -F': ' '{print $2}')
    echo "Firewalld status: $out"
  else
    echo "Firewalld status: not active or not installed"
  fi

  if command -v nft >/dev/null 2>&1; then
    out=$(systemctl status nftables | grep "Active:" | sed -e 's/^[^[:alpha:]]\+//' | awk -F': ' '{print $2}')
    echo "Nftables status: $out"
  else
    echo "Nftables status: not found"
  fi

  if command -v fail2ban >/dev/null 2>&1; then
    out=$(systemctl status fail2ban | grep "Active:" | sed -e 's/^[^[:alpha:]]\+//' | awk -F': ' '{print $2}')
    echo "Fail2ban status: $out"
  else
    echo "Fail2ban status: not found"
  fi
echo

echo -e "\e[0;33m##### 12. Sockets discovery #####\e[0m"
  out=$(ss -t4lnp | grep LISTEN | grep -vE "(127.0.0.1)" | awk '{print $4,$5}' | column -t)
  socketcount=$(ss -t4lnp | grep LISTEN | grep -vE "(127.0.0.1)" | wc -l)
  if [ -z "$out" ]; then
    echo "No listen socket found"
  else
    echo "Listen sockets: $socketcount"
    echo "$out"
  fi
echo

echo -e "\e[0;33m##### 13. Time zone information #####\e[0m"
  timedatectl | grep zone | sed -e 's/^[^[:alpha:]]\+//'
echo

echo -e "\e[0;33m##### 14. Users information #####\e[0m"
#
  usercount=$(getent passwd | awk -F: '{if($7=="/bin/bash")print $1}' | grep -wv root | wc -l)
  echo "Existing real users: $usercount"
    getent passwd | awk -F: '{if($7=="/bin/bash")print $1}' | grep -wv root
#
  out=$(getent group sudo | cut -d: -f4 | sed '/^[[:space:]]*$/d')
  pusercount=$(getent group sudo | cut -d: -f4 | sed '/^[[:space:]]*$/d' | wc -l)
    if [ -z "$out" ]; then
      echo "No users with elevated privileges found"
    else
      echo "Privileged users: $pusercount"
      echo "$out"
    fi
#
  nullpasscount=$(cat /etc/shadow | awk -F: '($2 == "" ) {print $1}' | sed '/^[[:space:]]*$/d' | wc -l)
  out=$(cat /etc/shadow | awk -F: '($2 == "" ) {print $1}' | sed '/^[[:space:]]*$/d')
    if [ -z "$out" ]; then
      echo "No users with empty password found"
    else
      echo "Users with null passwords: $nullpasscount"
      echo "$out"
    fi
#
  nopasscount=$(grep -r "NOPASSWD" /etc/sudoers /etc/sudoers.d | wc -l)
  out=$(grep -r "NOPASSWD" /etc/sudoers /etc/sudoers.d | cut -d':' -f2-)
    if [ -z "$out" ]; then
      echo "No users launch commands without password"
    else
      echo "Users launch commands without password: $nopasscount"
      echo "$out"
    fi
echo

echo -e "\e[0;33m##### 15. Secure shell settings #####\e[0m"
  if [ -f /etc/ssh/sshd_config ]; then
    grep -E 'PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|Listen|Port' /etc/ssh/sshd_config | grep -v '^# ' | grep -v '::'
  else
    echo "Configuration file not found"
  fi
echo

echo -e "\e[0;33m##### 16. Container applications #####\e[0m"
  out=$(docker ps --no-trunc 2>/dev/null)
  dockercount=$(docker ps --no-trunc 2>/dev/null | wc -l)
    if [ -z "$out" ]; then
      echo "No running containers found"
    else
      echo "Docker containers: $dockercount"
      echo "$out"
    fi
echo

echo -e "\e[0;33m##### 17. Installed databases #####\e[0m"
check_mysql() {
  if command -v mysql >/dev/null 2>&1; then
    out=$(mysql --version)
    echo "MySQL installed version: $out"
  else
    echo "MySQL not found"
    fi
}
check_postgresql() {
  if command -v psql >/dev/null 2>&1; then
    out=$(psql --version)
    echo "PostgreSQL installed version: $out"
  else
    echo "PostgreSQL not found"
  fi
}
check_sqlite() {
  if command -v sqlite3 >/dev/null 2>&1; then
    out=$(sqlite3 --version)
    echo "SQLite installed version: $out"
  else
    echo "SQLite not found"
  fi
}
check_mysql
check_postgresql
check_sqlite
echo

echo -e "\e[0;33m##### 18. Web publications #####\e[0m"
  if command -v nginx &> /dev/null; then
    out=$(systemctl status nginx  | grep "Active:" | sed -e 's/^[^[:alpha:]]\+//')
    echo "Web server NGINX status: $out"
    nginx -T | grep server_name | grep -vE "(configuration|bucket|redirect|example)"
  elif command -v apache &> /dev/null; then
    out=$(systemctl status apache  | grep "Active:" | sed -e 's/^[^[:alpha:]]\+//')
    echo "Web server APACHE status: $out"
  else
    echo "No Web server and published resources found"
  fi
echo

# Checking monitoring agents
echo -e "\e[0;33m##### 18. System monitoring status #####\e[0m"
if command systemctl status zabbix-agent &> /dev/null; then
  systemctl status zabbix-agent | grep "Active:" | sed -e 's/^[^[:alpha:]]\+//'
  ZBX=$(grep -vE 'Example|# Server=' /etc/zabbix/zabbix_agentd.conf | grep "Server=" | sed 's/.*=//')
  echo "Server: $ZBX"
    if ping -c 3 $ZBX &> /dev/null; then
      echo "Ping status: Alive"
    else
      echo "Ping status: Down"
    fi
    if nc -z -w2 $ZBX 10050 2> /dev/null; then
      echo "Connect to TCP port: Connected"
    else
      echo "Connect to TCP port: No connection"
    fi
elif command systemctl status zabbix-agent2 &> /dev/null; then
  systemctl status zabbix-agent2 | grep "Active:" | sed -e 's/^[^[:alpha:]]\+//'
  ZBX2=$(grep -vE 'Example|# Server=' /etc/zabbix/zabbix_agentd2.conf | grep "Server=" | sed 's/.*=//')
  echo "Server: $ZBX2"
    if ping -c 3 $ZBX2 &> /dev/null; then
      echo "Ping status: Alive"
    else
      echo "Ping status: Down"
    fi
    if nc -z -w2 $ZBX2 10050 2> /dev/null; then
      echo "Connect to TCP port: Connected"
    else
      echo "Connect to TCP port: No connection"
    fi
else
  echo "Monitoring agents not found"
fi
echo

echo -e "\e[0;33m##### 19. All running services #####\e[0m"
  service --status-all 2>/dev/null | grep "+" | awk '{print $4}' | grep -vE "(apparmor|bluetooth|cron|cups|dbus|gdm|kmod|networking|plymouth|procps|rpcbind|udev|sensors)"
echo

}


# Function send to WebDAV folder
send_to_webdav() {
URL="work.sharegate.ru"

# Отправка файла
if ping -c 3 $URL &> /dev/null; then
  curl -T $ARCHIVE https://$username:$password@work.sharegate.ru/audit/$FILENAME-audit.tar.gz  > /dev/null 2>&1
else
  echo "Report was not sent to WebDAV folder"
fi
}

# Write to file and change owner
if [[ "${output^^}" == "Y" ]]; then
  script_logo >> $RAWDATA
  echo "Script v. $VERSION by Andrey K." >> $RAWDATA
  echo "The audit was carried out in $(date '+%d/%m/%Y %H:%M:%S')" >> $RAWDATA
  perform_audit >> $RAWDATA
  sed 's/\x1b[[0-9;]*m//g' $RAWDATA > $REPORT
  tar -czf $ARCHIVE -C /tmp $FILENAME-audit.txt
#  zip $FILENAME-audit.zip /tmp/$FILENAME-audit.txt
  chown $RUSER:$RUSER $REPORT
  send_to_webdav
else
  perform_audit
fi

# Message about successful completion of the script
echo
echo "Success!"
echo

# Cleaning up traces of presence
rm -f $RAWDATA $REPORT $ARCHIVE $WORKFILE
history -c && history -w

# Calculating script execution time
END=$(date +%s)
DIFF=$(( END - START ))
echo "Script completed in $DIFF seconds"
echo

exit 0
