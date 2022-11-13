#!/bin/bash
export
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

cdrdb="asteriskcdrdb"
cdrtable="cdr"
celtable="cel"
dbuser="freepbx"
dbpass="pL0i#b3Y6tz"
datedir=$(date +"%Y/%m/%d")

if ! [ -d /mnt/nfs/monitor/$datedir ]; then
  mkdir -p /mnt/nfs/monitor/$datedir
fi

cd /var/spool/asterisk/outgoing/$datedir

for i in `find ./ -type f -name "*.mp3"`
  do
    if [ -e "$i" ]
      then
        file=`basename "$i" .mp3`;
        # Replace from CDR Reports
        mysql --user="$dbuser" --password="$dbpass" --database="$cdrdb" --execute='UPDATE '$cdrtable' SET \
        recordingfile="'$file'.mp3" WHERE recordingfile="'$file'.wav";';
        # Replace from UCP Reports
        mysql --user="$dbuser" --password="$dbpass" --database="$cdrdb" --execute='UPDATE '$celtable' SET \
        appdata=REPLACE(appdata, "'$datedir'/'$file'.wav", "/mnt/nfs/monitor/'$datedir'/'$file'.mp3");';
        mv /var/spool/asterisk/outgoing/$datedir/$i /mnt/nfs/monitor/$datedir/$i
        chown -R asterisk. /var/spool/asterisk/monitor/$datedir
    fi
done
