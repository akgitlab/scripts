Instructions:

 

1) Copy the link location of the script.

2) SSH into your Ubuntu/Debian machine, and login as root. ( Ubuntu | sudo -i | Debian | su )

2a) Make sure the ca-certificates package is installed.

apt-get update; apt-get install ca-certificates wget -y
3) Download the script by executing the following command. ( change it to your wanted version )

wget https://get.glennr.nl/unifi/install/unifi-6.5.55.sh
Install the latest and greatest UniFi Network application with 1 line. ( copy paste )
rm unifi-latest.sh &> /dev/null; wget https://get.glennr.nl/unifi/install/install_latest/unifi-latest.sh && bash unifi-latest.sh
4) Now run the script with the command below.

bash unifi-6.5.55.sh
The script has multiple options:
Option: --help
Shows script options and information.
Option: --skip
Skip any kind of manual input.
Option: --skip-swap
Skip swap file check/creation.
Option: --add-repository
Add UniFi Repository if --skip is used.
Option: --local-controller
Inform script that it's a local controller, to open port 10001/dup ( discovery ).
Option: --custom-url [argument]
Manually provide a UniFi Network application download URL. ( argument is optional )
example: --custom-url https://dl.ui.com/unifi/5.13.29/unifi_sysvinit_all.deb
Option: --v6
Run the Let's Encrypt script in IPv6 mode.
Option: --email [argument]
Specify what email address you want to use for Let's Encrypt renewal notifications.
example: --email glenn@glennr.nl
Option: --fqdn [argument]
Specify what domain name ( FQDN ) you want to use, you can specify multiple domain names with : as separator,.
Example: --fqdn glennr.nl:www.glennr.nl
Option: --server-ip [argument]
Specify the server IP address manually.
example: --server-ip 1.1.1.1
Option: --retry [argument]
Specify how many times the Let's Encrypt should retry the challenge/hostname resolving.
example: --retry 5
Option: --external-dns [argument] 
Use external DNS server to resolve the FQDN.
example: --external-dns 1.1.1.1
Option: --force-renew
Force renew the certificates.
Option: --dns-challenge
Runs the Let's Encrypt script in DNS mode instead of HTTP.
Option: --private-key [argument]
Specify path to your private key (paid certificate).
Example: --private-key /tmp/PRIVATE.key
Option: --signed-certificate [argument]
Specify path to your signed certificate (paid certificate).
example: --signed-certificate /tmp/SSL_CERTIFICATE.cer
Option: --chain-certificate [argument]
Specify path to your chain certificate (paid certificate).
example: --chain-certificate /tmp/CHAIN.cer
Option: --intermediate-certificate [argument]
Specify path to your intermediate certificate (paid certificate).
example: --intermediate-certificate /tmp/INTERMEDIATE.cer
Option: --own-certificate
Requirement if you want to import your own paid certificates with the use of --skip
 
Example command to run the script:
The example command installs the UniFi Network applicationwith Let's Encrypt certificates without any input from the user for glennr.nl and www.glennr.nl with email address glenn@glennr.nl for the renewal notifications.
bash unifi-5.13.29.sh --skip --fqdn glennr.nl:www.glennr.nl --email glenn@glennr.nl
5) Once the installation is completed browse to your server IP address.

https://ip.of.your.server:8443
6) Kudo/Upvote my post 😀

 

--------------------------------------------------------------

ALL includes support for..

- Ubuntu Precise Pangolin ( 12.04 )  
- Ubuntu Trusty Tahr ( 14.04 )
- Ubuntu Xenial Xerus ( 16.04 )
- Ubuntu Bionic Beaver ( 18.04 )
- Ubuntu Cosmic Cuttlefish ( 18.10 )
- Ubuntu Disco Dingo ( 19.04 )
- Ubuntu Eoan Ermine ( 19.10 )
- Ubuntu Focal Fossa ( 20.04 )
- Ubuntu Groovy Gorilla ( 20.10 )
- Ubuntu Hirsute Hippo ( 21.04 )
- Ubuntu Impish Indri ( 21.10 )
- Ubuntu Jammy Jellyfish ( 22.04 )
- Ubuntu Kinetic Kudu ( 22.10 )
- Ubuntu Lunar Lobster ( 23.04 )
- Debian Jessie ( 8 )
- Debian Stretch ( 9 )
- Debian Buster ( 10 )
- Debian Bullseye ( 11 )
- Debian Bookworm ( 12 )
- Linux Mint 13 ( Maya )
- Linux Mint 17 ( Qiana | Rebecca | Rafaela | Rosa )
- Linux Mint 18 ( Sarah | Serena | Sonya | Sylvia )
- Linux Mint 19 ( Tara | Tessa | Tina | Tricia )
- Linux Mint 20 ( Ulyana | Ulyssa | Uma | Una )
- Linux Mint 21 ( Vanessa )
- Linux Mint 4 ( Debbie )
- Linux Mint 5 ( Elsie )
- MX Linux 18 ( Continuum )
- Progress-Linux ( Engywuck )
- Parrot OS
- Elementary OS
- Deepin Linux
- Kali Linux ( rolling )

 

 

6.5.x

 

Installation script for UniFi 6.5.55 - ALL ( see list above for supported distributions )

 

7.0.x

 

Installation script for UniFi 7.0.20 - ALL ( see list above for supported distributions )

Installation script for UniFi 7.0.21 - ALL ( see list above for supported distributions )

Installation script for UniFi 7.0.22 - ALL ( see list above for supported distributions )

Installation script for UniFi 7.0.23 - ALL ( see list above for supported distributions )

Installation script for UniFi 7.0.25 - ALL ( see list above for supported distributions )

7.1.x

 

Installation script for UniFi 7.1.61 - ALL ( see list above for supported distributions )

Installation script for UniFi 7.1.65 - ALL ( see list above for supported distributions )

Installation script for UniFi 7.1.66 - ALL ( see list above for supported distributions )

Installation script for UniFi 7.1.67 - ALL ( see list above for supported distributions )

Installation script for UniFi 7.1.68 - ALL ( see list above for supported distributions )

7.2.x

 

Installation script for UniFi 7.2.91 - ALL ( see list above for supported distributions )

Installation script for UniFi 7.2.92 - ALL ( see list above for supported distributions )

Installation script for UniFi 7.2.93 - ALL ( see list above for supported distributions )

Installation script for UniFi 7.2.94 - ALL ( see list above for supported distributions )

Installation script for UniFi 7.2.95 - ALL ( see list above for supported distributions )

7.3.x

 

Installation script for UniFi 7.3.76 - ALL ( see list above for supported distributions )

 

 

Old Installation Scripts

 

You can download older script versions from HERE.

 

Version History

 

CLICK HERE to view the changelog.

 


I have added a second script that is focused on only updating the UniFi Network application/controller.

This script includes a solution for updating from 5.0.x to the latest versions

 

You can download the script HERE

 

Instructions:

 

1) Copy the link location of the script.

2) SSH into your Ubuntu/Debian machine, and login as root. ( Ubuntu | sudo -i | Debian | su )

2a) Users with a UDM/UDM-Pro running UniFi OS have to first enter the shell with unifi-os shell.

3) Make sure the ca-certificates package is installed.

apt-get update; apt-get install ca-certificates wget -y
4) Execute the following commands to download the script.

wget https://get.glennr.nl/unifi/update/unifi-update.sh
Run this 1 liner if you wan't to do step 3/4/5 in 1 go.
rm unifi-update.sh &> /dev/null; wget https://get.glennr.nl/unifi/update/unifi-update.sh && bash unifi-update.sh
5) Now run the script with the command below.

bash unifi-update.sh
The script has multiple options:
Option: --help
Shows script options and information.
Option: --skip
Skip manual input to automate option '--archive-alerts' and '--delete-events'..
Option: --archive-alerts
Archive all alerts, it will only run this and stop the script if you use this option.
Option: --delete-events
Delete all events, it will only run this and stop the script if you use this option.
Option: --custom-url [argument]
Manually provide a UniFi Network application download URL. ( argument is optional )
example: --custom-url https://dl.ui.com/unifi/5.13.29/unifi_sysvinit_all.deb
