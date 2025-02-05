#!/bin/bash

# System audit script
# Andrey Kuznetsov, 2025.02.05
# Telegram: https://t.me/akmsg

# This is a system audit bash script to gather instantly information about your Linux system
# which can also help you in the process of hardening.


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

# Real username
RUSER=$(who | awk '{print $1}' | head -1)

# Set report file path
REPORT="/tmp/$RNAME-audit.txt"

# For timer to script
START=$(date +%s)

# Clearing the screen from previously entered commands
clear -x

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
  echo -e "Welcome to system audit of your Linux system by AK"
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
      echo "Result will be saved to $REPORT"
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
echo "Please wait to finish system audit for $RNAME."
sleep 1
echo

# Function to perform audit
perform_audit() {

echo -e "\e[0;33mScript started at $(date '+%d/%m/%Y %H:%M:%S')\e[0m"
echo
echo -e "\e[0;33m##### 1. Hardware information #####\e[0m"
  hostnamectl | sed -e 's/^[^[:alpha:]]\+//' | grep -vE "(Icon|hostname|Kernel|Operating|Firmware|ID)" | sort -n
  lscpu | grep -E 'Vendor|Model name|Core|Virtualization' | grep -vE "(BIOS Model name|Vendor ID)" | sed -e "s/[[:space:]]\+/ /g"
  out=$(awk '/MemTotal/ {printf "%.2f GB\n", $2/1024/1024}' /proc/meminfo)
  echo "Available memory: $out"
echo

echo -e "\e[0;33m##### 2. Kernel information #####\e[0m"
  cat /proc/sys/kernel/{osrelease,version} | tr -d '#' | sort -n
  out=$(dmesg -H | grep -i "error" | sed 's/^[^a-zA-Z]*//' | uniq 2>/dev/null)
    if [ -z "$out" ]; then
      echo "No kernel errors found."
    else
      echo "~"
      echo "$out"
    fi
echo

echo -e "\e[0;33m##### 3. System runtime information #####\e[0m"
  out=$(uptime -p | cut -d " " -f2-)
    if [ -z "$out" ]; then
      echo "No information about uptime."
    else
      echo "System uptime: $out"
      echo "System boot at: $(who -b | awk '{print $3, $4}' | xargs -I {} date -d "{}" +"%d/%m/%Y %H:%M:%S")"
    fi
echo

echo -e "\e[0;33m##### 4. Distribution information #####\e[0m"
  lsb_release -a | sed -e "s/[[:space:]]\+/ /g"
  echo "Installed at: $(ls -lct --time-style=+"%d/%m/%Y %H:%M:%S" / | tail -1 | awk '{print $6, $7}')"
  echo "Last updated at: $(date -d @"$(stat -c %Y /var/cache/apt/)" +"%d/%m/%Y %H:%M:%S")"
echo

echo -e "\e[0;33m##### 5. Checks packages broken dependencies #####\e[0m"
  apt-get check
echo

echo -e "\e[0;33m##### 6. Network interfaces addresses #####\e[0m"
  ip a | grep -E 'inet ' | awk '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//'
echo

echo -e "\e[0;33m##### 7. Routing table #####\e[0m"
  ip route
echo

echo -e "\e[0;33m##### 8. Time zone information #####\e[0m"
  timedatectl | grep zone | sed -e 's/^[^[:alpha:]]\+//'
echo

echo -e "\e[0;33m##### 9. Secure shell settings #####\e[0m"
  if [ -f /etc/ssh/sshd_config ]; then
    grep -E 'PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|Listen|Port' /etc/ssh/sshd_config
  else
    echo "Configuration file not found."
  fi
echo

echo -e "\e[0;33m##### 10. Users information #####\e[0m"
  echo "All users except system:"
    getent passwd | awk -F: '{if($7=="/bin/bash")print $1}' | grep -wv root
  echo "Privileged users:"
    out=$(getent group sudo | cut -d: -f4 | sed '/^[[:space:]]*$/d')
      if [ -z "$out" ]; then
        echo "No users with elevated privileges found."
      else
        echo "$out"
      fi
  echo "Users with null passwords:"
    out=$(cat /etc/shadow | awk -F: '($2 == "" ) {print $1}' | sed '/^[[:space:]]*$/d')
      if [ -z "$out" ]; then
        echo "No users with empty password found."
      else
        echo "$out"
      fi
  echo "Users may run the following commands:"
    sudo -l | sed '/^[[:space:]]*$/d' | sed -e 's/^[^[:alpha:]]\+//'
echo

echo -e "\e[0;33m##### 11. Explicitly specified passwords #####\e[0m"
SEARCH_DIR="/etc"
EXCLUDE_FILES=("file1.conf" "file2.conf")
EXCLUDE_PATTERN=$(printf "! -name %s " "${EXCLUDE_FILES[@]}")
  out=$(find "$SEARCH_DIR" -type f $EXCLUDE_PATTERN -exec grep -E -i 'password=|secret=|token=' {} \; 2>/dev/null)
  if [ -z "$out" ]; then
    echo "No clear text passwords found."
  else
    echo "$out"
  fi
echo

echo -e "\e[0;33m##### 12. Installed databases #####\e[0m"
check_mysql() {
  if command -v mysql >/dev/null 2>&1; then
    out=$(mysql --version)
    echo "MySQL version: $out"
  else
    echo "MySQL not found."
    fi
}
check_postgresql() {
  if command -v psql >/dev/null 2>&1; then
    out=$(psql --version)
    echo "PostgreSQL version: $out"
  else
    echo "PostgreSQL not found."
  fi
}
check_sqlite() {
  if command -v sqlite3 >/dev/null 2>&1; then
    out=$(sqlite3 --version)
    echo "SQLite version: $out"
  else
    echo "SQLite not found."
  fi
}
check_mysql
check_postgresql
check_sqlite
echo

echo -e "\e[0;33m##### 13. Web publications #####\e[0m"
  if command -v nginx &> /dev/null; then
    echo "Web server NGINX status:"
    systemstl status nginx
    nginx -T | grep server_name
  elif command -v apache &> /dev/null; then
    echo "Web server APACHE status:"
    systemstl status apache
  else
    echo "No published resources found."
  fi
echo

echo -e "\e[0;33m##### 14. System monitoring status #####\e[0m"
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
  echo "Monitoring agents not found."
fi
echo

echo -e "\e[0;33m##### 15. All running services #####\e[0m"
  service --status-all 2>/dev/null | grep "+" | awk '{print $4}' | grep -vE "(apparmor|bluetooth|cron|cups|dbus|gdm|kmod|networking|plymouth|procps|rpcbind|udev|sensors)"
echo


}

# Function write to file
if [[ "${output^^}" == "Y" ]]; then
  perform_audit >> $REPORT
  chown $RUSER:$RUSER $REPORT
else
  perform_audit
fi

echo
echo "################################################################"
echo
END=$(date +%s)
DIFF=$(( END - START ))
echo "Script completed in $DIFF seconds."
echo

exit 0



#####################################################################################################################################################################


Дополнить отсюда: https://github.com/sokdr/LinuxAudit
https://ipiskunov.blogspot.com/2016/11/linux.html

# Проверка наличия файрвола
print_section "Проверка наличия файрвола"
if command -v ufw &> /dev/null; then
    echo "Статус UFW:"
    ufw status
elif command -v firewall-cmd &> /dev/null; then
    echo "Статус Firewalld:"
    firewall-cmd --state
else
    echo "Файрвол не найден."
fi

https://dzen.ru/a/ZMp_gM3texUMQdny

Сайты
https://itisgood.ru/2024/03/01/spisok-vsekh-virtualnikh-khostov-v-nginx/https://itisgood.ru/2024/03/01/spisok-vsekh-virtualnikh-khostov-v-nginx/https://itisgood.ru/2024/03/01/spisok-vsekh-virtualnikh-khostov-v-nginx/


### Old script ###
touch /tmp/audit/Рекомендации.txt
hostnamectl > /tmp/audit/Описание.txt
dmidecode -s system-manufacturer >> /tmp/audit/Описание.txt
dmesg | grep -i hypervisor >> /tmp/audit/Описание.txt
lscpu > /tmp/audit/Процессор.txt
free -h > /tmp/audit/Память.txt
cat /etc/*release > /tmp/audit/"Информация о релизе.txt"
getent passwd | awk -F: '{if($7=="/bin/bash")print $1}' | grep -wv root > /tmp/audit/"Список пользователей.txt"
getent group sudo | cut -d: -f4 > /tmp/audit/"Список привилегированных пользователей.txt"
apt list --installed > /tmp/audit/"Список установленных пакетов.txt"
ps -eF > /tmp/audit/"Запущенные процессы.txt"
ss -t4 state established > /tmp/audit/"Установленные соединения.txt"
ss -tl > /tmp/audit/"Прослушиваемые порты.txt"
for user in $(cut -d':' -f1 /etc/passwd); do crontab -u $user -l; done > /tmp/audit/"Задания планировщика.txt"
iptables-save | sudo tee /tmp/audit/"Правила фаервола.txt" > /dev/null
ip a > /tmp/audit/"Сетевые интерфейсы.txt"
docker ps --no-trunc > /tmp/audit/Контейнеры.txt
lsblk > /tmp/audit/Диски.txt


# Finish actions
rm /home/$RUSER/post-install.sh
