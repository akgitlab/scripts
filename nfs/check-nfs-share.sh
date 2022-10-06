#!/bin/sh
df -h | grep nfs
if [ $? -eq 0 ]
then exit
else
mount -t nfs 10.0.180.95:/var/spool/asterisk/  /mnt/nfs/
fi
