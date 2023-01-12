#!/bin/bash

# Nftables firewall presets for mail gateway server
# Andrey Kuznetsov, 2023.01.12
# Telegram: https://t.me/akmsg

# WARNING! Carefully check all the settings, because by applying this script you can block your access to the server!

# Get variables
nft="/sbin/nft";

# User confirmation request
read -r -p "Are you sure you want to execute the initial firewall configuration script? [y/n] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]
then

        ${nft} flush ruleset
        #------------------inet filter table-------------------#
        ${nft} add table inet filter
        ${nft} add chain inet filter input { type filter hook input priority 0\; policy accept\; }
        ${nft} add chain inet filter forward { type filter hook forward priority 0\; policy accept\; }
        ${nft} add chain inet filter output { type filter hook output priority 0\; policy accept\; }
        #-----------------------input--------------------------#
        ${nft} add rule inet filter input ct state related,established counter accept
        ${nft} add rule inet filter input ct state invalid counter drop;
        ${nft} add rule inet filter input iifname "lo" counter accept
        ${nft} add rule inet filter input ip protocol icmp counter accept
        #---------------------admin input----------------------#
        ${nft} add rule inet filter input ip saddr 10.1.1.48/32 tcp dport 22 counter accept
        ${nft} add rule inet filter input ip saddr 10.3.44.0/24 tcp dport 22 counter accept
        ${nft} add rule inet filter input ip saddr 10.250.250.0/24 tcp dport 22 counter accept
        ${nft} add rule inet filter input ip saddr 10.3.44.0/24 tcp dport { 80, 443 } counter accept
        ${nft} add rule inet filter input ip saddr 10.0.22.21/32 tcp dport { 22, 80, 443, 10050 } counter accept
        ${nft} add rule inet filter input tcp dport { 22, 80, 443, 10050 } counter drop
        #--------------------client input----------------------#
        ${nft} add rule inet filter input ip saddr 92.53.82.188/32 tcp dport 25 counter drop
        ${nft} add rule inet filter input ip saddr 0.0.0.0/0 tcp dport 25 counter accept
        #----------------------forward-------------------------#
        ${nft} add rule inet filter forward ct state new tcp dport 25 counter accept
        ${nft} add rule inet filter forward counter reject with icmp type host-prohibited
        #-----------------------output-------------------------#
        ${nft} add rule inet filter output counter accept
        #------------------------drop--------------------------#
        ${nft} add rule inet filter input counter reject with icmp type host-prohibited

        ${nft} -s list ruleset | tee /etc/nftables.conf > /dev/null 2>&1

        echo "Firewall configuration applied successfully"

else
        echo "Changes canceled"

fi
