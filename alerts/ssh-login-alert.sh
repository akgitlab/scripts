#!/bin/bash

# User login notification via ssh
# Andrey Kuznetsov, 2022.02.20

# Save it as /etc/profile.d/ssh-telegram.sh
# Use jq to parse JSON from ipinfo.io

# Get variables
USERID="-1001434879872"
KEY="1721564204:AAF68HtpXqgvSVfw0xxlXtkClbkB2mZllvI"
TIMEOUT="10"
URL="https://api.telegram.org/bot$KEY/sendMessage"
DATE_EXEC="$(date "+%d %b %Y %H:%M")"
TMPFILE='/tmp/ipinfo-$DATE_EXEC.txt'

# Send notification
if [ -n "$SSH_CLIENT" ]; then
        IP=$(echo $SSH_CLIENT | awk '{print $1}')
        PORT=$(echo $SSH_CLIENT | awk '{print $3}')
        HOSTNAME=$(hostname -f)
        IPADDR=$(hostname -I | awk '{print $1}')
        curl http://ipinfo.io/$IP -s -o $TMPFILE
        CITY=$(cat $TMPFILE | jq '.city' | sed 's/"//g')
        REGION=$(cat $TMPFILE | jq '.region' | sed 's/"//g')
        COUNTRY=$(cat $TMPFILE | jq '.country' | sed 's/"//g')
        ORG=$(cat $TMPFILE | jq '.org' | sed 's/"//g')
        TEXT="$DATE_EXEC: ${USER} logged in to $HOSTNAME ($IPADDR) from $IP - $ORG - $CITY, $REGION, $
        curl -s --max-time $TIMEOUT -d "chat_id=$USERID&disable_web_page_preview=1&text=$TEXT" $URL >$
        rm $TMPFILE
fi
