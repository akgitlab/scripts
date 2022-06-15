#!/bin/bash

nft="/sbin/nft";

echo "Are you sure you want to execute the initial configuration script? [y/n]"
read q
if [[ "$q" == "y" ]];
then

        ${nft} flush ruleset
        #-----------------ip filter table-------------------#
        ${nft} add table ip filter
        ${nft} add chain ip filter INPUT { type filter hook input priority 0\; policy accept\; }
        ${nft} add chain ip filter FORWARD { type filter hook forward priority 0\; policy accept\; }
        ${nft} add chain ip filter OUTPUT { type filter hook output priority 0\; policy accept\; }
        #-----------------INPUT-------------------#
        ${nft} add rule ip filter INPUT ct state related,established counter accept
        ${nft} add rule ip filter INPUT ct state invalid counter drop;
        ${nft} add rule ip filter INPUT iifname "lo" counter accept
        ${nft} add rule ip filter INPUT ip protocol icmp counter accept
        #-----------------ADMIN INPUT-------------------#
        ${nft} add rule ip filter INPUT ip saddr 10.3.44.0/24 tcp dport 22 counter accept
        ${nft} add rule ip filter INPUT tcp dport 22 counter drop
        ${nft} add rule ip filter INPUT ip saddr 10.3.44.0/24 tcp dport { 80, 443 } counter accept
        ${nft} add rule ip filter INPUT tcp dport { 80, 443 } counter drop
        #-----------------ZABBIX INPUT-------------------#
        ${nft} add rule ip filter INPUT ip saddr 10.0.22.21 tcp dport 10050 counter accept
        ${nft} add rule ip filter INPUT tcp dport 10050 counter drop
        #-----------------SIP INPUT-------------------#
        ${nft} add rule ip filter INPUT ip saddr 10.3.44.0/24 udp dport { 5060, 5061 } counter accept
        #-----------------SIP PROVIDER INPUT-------------------#
        ${nft} add rule ip filter INPUT ip saddr sip.beeline.ru udp dport 5000-5170 counter accept
        ${nft} add rule ip filter INPUT ip saddr sip.beeline.ru udp dport 10000-20000 counter accept
        #-----------------RTP INPUT-------------------#
        ${nft} add rule ip filter INPUT ip saddr 10.0.1.0/24 udp dport 5000-5170 counter accept
        ${nft} add rule ip filter INPUT ip saddr 10.0.1.0/24 udp dport 10000-20000 counter accept
        #-----------------FORWARD-------------------#
        ${nft} add rule ip filter FORWARD counter reject with icmp type host-prohibited
        ${nft} add rule ip filter FORWARD ct state new udp dport 10000-20000 counter accept
        #-----------------OUTPUT-------------------#
        ${nft} add rule ip filter OUTPUT counter accept
        #-----------------DROP-------------------#
        ${nft} add rule ip filter INPUT counter drop
        ${nft} add rule ip filter INPUT counter reject with icmp type host-prohibited

        echo "Done!"
else
        echo "Cancel"
fi
