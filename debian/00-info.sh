#!/usr/bin/env bash

# OS available?
if [ -f /etc/os-release ]; then
    source /etc/os-release
else
    PRETTY_NAME="Linux"
fi

# Welcome message
cat /etc/update-motd.d/00-msg
printf "\n%s\n" "$(date)"
printf "Distro: %s | Core: %s\n" "$PRETTY_NAME" "$(uname -r)"
echo "Powered by Debian is a distribution of Free Software and maintained and updated through the work of many users who volunteer..."
echo ""

# Show failed services
systemctl list-units --state failed --type service | awk 'FNR>1' | grep failed
echo ""
