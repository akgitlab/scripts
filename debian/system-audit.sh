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

#!/bin/bash

# System audit scrip
# Andrey Kuznetsov, 2025.01.29
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
  echo -e "Welcome to system audit script of your Linux system by AK"
  echo
  echo "Script will automatically gather the required info."
  echo "The checklist can help you in the process of hardening your system."
  echo "It has been tested for Debian Linux Distro."
}
start_script

sleep 3

# User privilege check
if [[ $EUID -ne 0 ]]
then
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
echo "System audit for $RNAME let's continue, please wait for it to finish."
START=$(date +%s)
echo

# Function to perform audit
perform_audit() {

# Date and time start
echo -e "\e[0;33mScript started at $(date '+%d/%m/%Y %H:%M:%S')\e[0m"
echo
echo -e "\e[0;33m##### 1. Hardware information #####\e[0m"
    hostnamectl | sed -e 's/^[^[:alpha:]]\+//' | grep -vE "(Icon|hostname|Kernel|Operating|Firmware|ID)" | sort -n
echo
echo -e "\e[0;33m##### 2. Kernel information #####\e[0m"
    cat /proc/sys/kernel/{ostype,osrelease,version}
    # or "uname -a"
echo
echo -e "\e[0;33m##### 3. Distribution information #####\e[0m"
    lsb_release -a | sed -e "s/[[:space:]]\+/ /g"
    echo "Installed at: $(ls -lct --time-style=+"%d/%m/%Y %H:%M:%S" / | tail -1 | awk '{print $6, $7}')"
echo

echo -e "\e[0;33m##### 3. Time zone information #####\e[0m"
    timedatectl | grep zone | sed -e 's/^[^[:alpha:]]\+//'
    # or "timedatectl status | grep "zone" | sed -e 's/^[ ]*Time zone: \(.*\) (.*)$/\1/g'"
    # or "timedatectl | sed -n 's/^\s*Time zone: \(.*\) (.*/\1/p'"
    # or "cat /etc/timezone"
echo

echo -e "\e[0;33m##### X. Secure shell settings #####\e[0m"
if [ -f /etc/ssh/sshd_config ]; then
    grep -E 'PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|Listen|Port' /etc/ssh/sshd_config
else
    echo "Configuration file not found."
fi
echo

echo -e "\e[0;33m##### X. Users information #####\e[0m"
    echo "All users (excluding system users):"
    getent passwd | awk -F: '{if($7=="/bin/bash")print $1}' | grep -wv root
    echo "Privileged users:"
    getent group sudo | cut -d: -f4 | sed '/^[[:space:]]*$/d'
    # For CentOS "lid -g wheel --"
    echo "Users with null passwords:"
    cat /etc/shadow | awk -F: '($2 == "" ) {print $1}' | sed '/^[[:space:]]*$/d'
    echo "Users may run the following commands:"
    sudo -l | sed '/^[[:space:]]*$/d' | sed -e 's/^[^[:alpha:]]\+//'



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
