#!/bin/bash

# Monitor for NFS file system mounted
# Andrey Kuznetsov, 2022.10.29
# Telegram: https://t.me/akmsg

# WARNING! Our Linux server monitoring script should be installed in the network or on the specific host where the NFS mount is running!


# Get user variables

SRV=$(grep -v '^#' /etc/zabbix/zabbix_agentd.conf  | grep -v '^$' | grep Server= | awk -F '=' '{print $2}')
TRAP=$(hostname -I)


# Get Remote NFS server IP

path=$1
ipaddr=$(mount -l -t nfs,nfs4,nfs2,nfs3 | grep -w "$path" | awk -F'[(|,|=|)]' '{ for(i=1;i<=NF;i++) if ($i == "addr") print $(i+1) }')


# Check if mountpoint exists

if [ "$ipaddr" ]
then
  echo "$ipaddr" |
  while read line
  do
    df -k ${MP} &> /dev/null &
    DFPID=$!
      for (( i=1 ; i<3 ; i++ ))
        do
          if ps -p $DFPID > /dev/null
          then
            sleep 1
          else
            break
          fi
        done
      if ps -p $DFPID > /dev/null
      then
        $(kill -s SIGTERM $DFPID &> /dev/null)
        echo -e "\033[0m\033[0m\033[31mRemote NFS volume is not mounted"
        tput sgr0
        zabbix_sender -z $SRV -s $TRAP -k vfs.fs.mp -o 0 > /dev/null 2>&1
      else
        echo -e "\033[32mRemote NFS volume is mounted"
        tput sgr0
        zabbix_sender -z $SRV -s $TRAP -k vfs.fs.mp -o 1 > /dev/null 2>&1
      fi
  done
fi
