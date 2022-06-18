#!/bin/bash

nft="/sbin/nft";

echo "Are you sure you want to execute the initial firewall configuration script? [y/n]"
read q
if [[ "$q" == "y" ]];
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
        ${nft} add rule inet filter input ip saddr 10.3.44.0/24 tcp dport 22 counter accept
        ${nft} add rule inet filter input ip saddr 10.3.44.0/24 tcp dport { 80, 443 } counter accept
        ${nft} add rule inet filter input ip saddr 10.0.22.21/32 tcp dport { 22, 80, 443, 5038, 8088, 10050 } counter accept
        ${nft} add rule inet filter input tcp dport { 22, 80, 443, 5038, 8088, 10050 } counter drop
        #-----------------sip provider input-------------------#
        ${nft} add rule inet filter input ip saddr sip.beeline.ru udp dport 5000-5170 counter accept
        ${nft} add rule inet filter input ip saddr sip.beeline.ru udp dport 10000-20000 counter accept
        #------------------sip client input--------------------#
        ${nft} add rule inet filter input ip saddr 10.0.1.0/24 udp dport 5000-5170 counter accept
        #------------------rtp client input--------------------#
        ${nft} add rule inet filter input ip saddr 10.0.1.0/24 udp dport 10000-20000 counter accept
        #----------------------forward-------------------------#
        ${nft} add rule inet filter forward ct state new udp dport 10000-20000 counter accept
        ${nft} add rule inet filter forward counter reject with icmp type host-prohibited
        #-----------------------output-------------------------#
        ${nft} add rule inet filter output counter accept
        #------------------------drop--------------------------#
        ${nft} add rule inet filter input ct state new udp dport 5000-5170 counter drop
        ${nft} add rule inet filter input ct state new udp dport 10000-20000 counter drop
        ${nft} add rule inet filter input counter reject with icmp type host-prohibited

        ${nft} -s list ruleset | tee /etc/nftables.conf > /dev/null 2>&1

        echo "Firewall configuration applied successfully"
else
        echo "Changes canceled"
fi
