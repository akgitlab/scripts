Дополнить отсюда: https://github.com/sokdr/LinuxAudit

#!/bin/bash

# Security audit bash script for Linux systems
# Andrey Kuznetsov, 2025.01.29
# Telegram: https://t.me/akmsg

# This is a security audit bash script to gather instantly information about your Linux system
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

# So let's begin...

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
  echo -e "Welcome to security audit script of your Linux system by AK"
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
