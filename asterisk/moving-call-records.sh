#!/bin/bash
export
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
datedir=$(date +"%Y/%m/%d")
if ! [ -d /mnt/nfs/monitor/$datedir ]; then
mkdir -p /mnt/nfs/monitor/$datedir
fi
cd /var/spool/asterisk/outgoing/$datedir
for i in $( find *.mp3 ); do
mv /var/spool/asterisk/outgoing/$datedir/$i /mnt/nfs/monitor/$datedir/$i
chown -R asterisk. /var/spool/asterisk/monitor/$datedir
done
