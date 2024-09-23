#!/bin/bash
touch /home/admin555/audit/Описание.txt
touch /home/admin555/audit/Рекомендации.txt
lscpu > /home/admin555/audit/Процессор.txt
free -h > /home/admin555/audit/Память.txt
cat /etc/*release > /home/admin555/audit/"Информация о релизе.txt"
cat /etc/passwd > /home/admin555/audit/"Список пользователей.txt"
getent group sudo > /home/admin555/audit/"Список привилегированных пользователей.txt"
apt list --installed > /home/admin555/audit/"Список установленных пакетов.txt"
ps -eF > /home/admin555/audit/"Запущенные процессы.txt"
ss -t4 state established > /home/admin555/audit/"Установленные соединения.txt"
ss -tl > /home/admin555/audit/"Прослушиваемые порты.txt"
for user in $(cut -d':' -f1 /etc/passwd); do crontab -u $user -l; done > /home/admin555/audit/"Задания планировщика.txt"
iptables-save | sudo tee /home/admin555/audit/"Правила фаервола.txt" > /dev/null
ip a > /home/admin555/audit/"Сетевые интерфейсы.txt"
docker ps --no-trunc > /home/admin555/audit/Контейнеры.txt
lsblk > /home/admin555/audit/Диски.txt
