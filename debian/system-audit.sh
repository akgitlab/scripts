#!/bin/bash

touch /tmp/audit/Рекомендации.txt
dmidecode -s system-manufacturer > /tmp/audit/Описание.txt
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
