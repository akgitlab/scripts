#!/bin/bash
export
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
datedir=$(date +"%Y/%m/%d")
if ! [ -d /mnt/nfs/monitor/$datedir ]; then
mkdir -p /mnt/nfs/monitor/$datedir
fi
cd /var/spool/asterisk/monitor/$datedir
for i in $( find *.WAV ); do
mv /var/spool/asterisk/monitor/$datedir/$i /mnt/nfs/monitor/$datedir/$i
ln -s /mnt/nfs/monitor/$datedir/$i /var/spool/asterisk/monitor/$datedir/$i
chown asterisk. /var/spool/asterisk/monitor/$datedir -R
done
