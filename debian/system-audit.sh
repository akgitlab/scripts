Дополнить отсюда: https://github.com/sokdr/LinuxAudit
https://ipiskunov.blogspot.com/2016/11/linux.html

Пользователи без пароля
cat /etc/shadow | awk -F: '$2 == ""'
или
cat /etc/shadow | awk -F: '($2 == "" ) {print $1}'

# Проверка настроек SSH
print_section "Настройки SSH"
if [ -f /etc/ssh/sshd_config ]; then
    echo "Настройки SSH:"
    grep -E 'PermitRootLogin|PasswordAuthentication|PubkeyAuthentication' /etc/ssh/sshd_config
else
    echo "Файл конфигурации SSH не найден."
fi

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

# Real username
RUSER=$(who | awk '{print $1}' | head -1)

# Hostname
RNAME=$(hostname)

# Set report file path
REPORT="/home/$RUSER/$RNAME-audit.txt"


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

# Request to save results
while true; do
    read -p "Would you like to save the output? [Y/N] " output
    case "${output^^}" in
        Y)
            echo "File will be saved to $REPORT"
            break
            ;;
        N)
            echo "OK, not saving moving on."
            break
            ;;
        *)
            echo "Invalid input. Please enter Y or N."
            ;;
    esac
done

# Date and time start audit
echo -e "\n$(date '+%d/%m/%Y %H:%M:%S')" >> $REPORT

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
