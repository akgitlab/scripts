#!/bin/bash
#------------------------------
# Script to manage vCenter  
# SSL certificates.
#
# Author: Vincent Santa Maria [vsantamaria@vmware.com]
# Version: 3.9
#------------------------------

#------------------------------
# Print section header
#------------------------------
function header() {
   printf "\n${CYAN}$1\n" | tee -a $LOG
   printf "%56s${NORMAL}\n" | tr " " "-" | tee -a $LOG
}

#------------------------------
# Print task description
#------------------------------
function task() {
  printf "%-43s" "$1" | tee -a $LOG
}

#------------------------------
# Print formatted task message with colored text
#------------------------------
function taskMessage() {
   printf "%13s\n" "[ ${1} ]" | sed "s/${1}/${!2}${1}${NORMAL}/" | tee -a $LOG
}

#------------------------------
# Print formatted status message with colored text
#------------------------------
function statusMessage() {
   printf "%13s\n" "${1}" | sed "s/${1}/${!2}${1}${NORMAL}/" | tee -a $LOG
}

#------------------------------
# Print formatted 'errror' message
#------------------------------
function errorMessage() {
   printf "%13s\n\n" "[ FAILED ]" | sed "s/FAILED/${RED}&${NORMAL}/" | tee -a $LOG
   printf "${YELLOW}${1}. Exiting...${NORMAL}\n\n" | tee -a $LOG
   
   exit 1
}

#------------------------------
# Print formatted 'valid' message
#------------------------------
function validMessage() {
   printf "%13s\n" "VALID" | sed "s/VALID/${GREEN}&${NORMAL}/" | tee -a $LOG
}

#------------------------------
# Print formatted 'no PNID' message
#------------------------------
function noPnidMessage() {
   printf "%13s\n" "NO PNID" | sed "s/NO PNID/${YELLOW}&${NORMAL}/" | tee -a $LOG
}

#------------------------------
# Print formatted 'expires soon' message
#------------------------------
function expireSoonMessage() {
   printf "%13s\n" "${1} DAYS" | sed -E "s/[0-9]+ DAYS/${YELLOW}&${NORMAL}/" | tee -a $LOG
}

#------------------------------
# Print formatted expired message
#
# @variable $LOG  string
#------------------------------
function expiredMessage() {
   printf "%13s\n" "EXPIRED" | sed "s/EXPIRED/${YELLOW}&${NORMAL}/" | tee -a $LOG
}

#------------------------------
# Print formatted 'mismatch' message
#------------------------------
function mismatchMessage() {
   printf "%13s\n" "MISMATCH" | sed "s/MISMATCH/${YELLOW}&${NORMAL}/" | tee -a $LOG
}

#------------------------------
# Set color variables
#------------------------------

function enableColor() {
   RED=$(tput setaf 1)
   GREEN=$(tput setaf 2)
   YELLOW=$(tput setaf 3)
   CYAN=$(tput setaf 6)
   NORMAL=$(tput sgr0)
}

#------------------------------
# Clear color variables for reports
#------------------------------

function disableColor() {
   RED=""
   GREEN=""
   YELLOW=""
   CYAN=""
   NORMAL=""
}

#------------------------------
# Pre-start operations
#------------------------------
function preStartOperations() {
   if [ ! -d $STAGE_DIR ]; then mkdir -p $STAGE_DIR; fi
   if [ ! -d $REQUEST_DIR ]; then mkdir -p $REQUEST_DIR; fi
   if [ ! -d $BACKUP_DIR ]; then mkdir -p $BACKUP_DIR; fi
   
   echo -n "$VMDIR_MACHINE_PASSWORD" > $STAGE_DIR/.machine-account-password
   chmod 640 $STAGE_DIR/.machine-account-password
   
   enableColor
}

#------------------------------
# Cleanup operations
#------------------------------
function cleanup() {
   if [ $CLEANUP -eq 1 ]; then
      rm -Rf $STAGE_DIR
   fi
   # remove color formatting from log
   sed -i -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" $LOG && sed -i "s/\x1B\x28\x42//g" $LOG
}

#------------------------------
# Get SSO administrator credentials
#------------------------------
function getSSOCredentials() {
   read -p $'\n'"Please enter a Single Sign-On administrator account [${VMDIR_USER_UPN_DEFAULT}]: " VMDIR_USER_UPN_INPUT

   if [ -z $VMDIR_USER_UPN_INPUT ]; then
      VMDIR_USER_UPN=$VMDIR_USER_UPN_DEFAULT
   else
      VMDIR_USER_UPN=$VMDIR_USER_UPN_INPUT
   fi

   echo "User has chosen the following Single Sign-On account: $VMDIR_USER_UPN" >> $LOG

   VMDIR_USER=$(echo $VMDIR_USER_UPN | awk -F'@' '{print $1}')
   read -s -p "Please provide the password for $VMDIR_USER_UPN: " VMDIR_USER_PASSWORD
   echo -n $VMDIR_USER_PASSWORD > $STAGE_DIR/.vmdir-user-password
   chmod 640 $STAGE_DIR/.vmdir-user-password
}

#------------------------------
# Verify SSO credentials
#------------------------------
function verifySSOCredentials() {
   VERIFIED=0
   ATTEMPT=1

   echo "Validating credentials for ${VMDIR_USER_UPN}" >> $LOG

   while [ $ATTEMPT -le 3 ]; do
      if ! $LDAP_SEARCH -LLL -h $VMDIR_FQDN -p 389 -b "cn=Servers,cn=$SSO_SITE,cn=Sites,cn=Configuration,$VMDIR_DOMAIN_DN" -D "cn=$VMDIR_USER,cn=users,$VMDIR_DOMAIN_DN" -y $STAGE_DIR/.vmdir-user-password "(objectclass=vmwDirServer)" cn 2>/dev/null 1>/dev/null; then
         echo "Invalid credentials for $VMDIR_USER_UPN (attempt $ATTEMPT)" >> $LOG
         read -s -p $'\n'"Invalid credentials, please enter the password for $VMDIR_USER_UPN: " VMDIR_USER_PASSWORD
         echo -n $VMDIR_USER_PASSWORD > $STAGE_DIR/.vmdir-user-password
         chmod 640 $STAGE_DIR/.vmdir-user-password
         ((++ATTEMPT))
      else
         VERIFIED=1
         echo "Credentials verified for $VMDIR_USER_UPN" >> $LOG
         break
      fi
   done

   if [ ${VERIFIED} = 0 ]; then
      printf "\n\n${YELLOW}Unable to verify credentials for $VMDIR_USER_UPN. Exiting...${NORMAL}\n\n" | tee -a $LOG
      exit
   fi
}

#------------------------------
# Check for a VECS store for the legacy Lookup Service cert
#------------------------------
function checkLookupServiceVECSStore() {
   if $VECS_CLI store list | grep STS_INTERNAL_SSL_CERT > /dev/null; then
      return 0
   else
      return 1
   fi
}

#------------------------------
# Check for a VECS store for the backup copies of certificates
#------------------------------
function checkVECSBackupStore() {
   if $VECS_CLI store list | grep BACKUP_STORE > /dev/null; then
      return 0
   else
      return 1
   fi
}

#------------------------------
# Resets the certificate status flags
#------------------------------
function resetCertStatusChecks() {
   CERT_STATUS_MESSAGE=""
   CERT_STATUS_EXPIRES_SOON=0
   CERT_STATUS_MISSING_PNID=0
   CERT_STATUS_KEY_USAGE=0
   CERT_STATUS_EXPIRED=0
   CERT_STATUS_NON_CA=0
   CERT_STATUS_BAD_ALIAS=0
}

#------------------------------
# Builds the expanded message detailng issues with certificates
#------------------------------
function buildCertificateStatusMessage() {
   if [ $CERT_STATUS_EXPIRES_SOON == 1 ]; then CERT_STATUS_MESSAGE+=" - One or more certificates are expiring within 30 days"$'\n'; fi
   
   if [ $CERT_STATUS_MISSING_PNID == 1 ]; then CERT_STATUS_MESSAGE+=" - One or more certificates are missing the PNID ($PNID) from the SAN entry"$'\n'; fi
   
   if [ $CERT_STATUS_KEY_USAGE == 1 ]; then CERT_STATUS_MESSAGE+=" - One or more certificates do not have the recommended Key Usage values"$'\n'; fi
   
   if [ $CERT_STATUS_EXPIRED == 1 ]; then CERT_STATUS_MESSAGE+=" - One or more certificates are expired"$'\n'; fi
   
   if [ $CERT_STATUS_NON_CA == 1 ]; then CERT_STATUS_MESSAGE+=" - One or more certificates are not CA certificates"$'\n'; fi
   
   if [ $CERT_STATUS_BAD_ALIAS == 1 ]; then CERT_STATUS_MESSAGE+=" - One or more entries in the TRUSTED_ROOTS store have an alias that is not the SHA1 thumbprint"$'\n'; fi     
}

#------------------------------
# Quick certificate status check
#------------------------------
function checkCerts() {
   resetCertStatusChecks
   
   header "Checking certifcate status"
   
   task "Checking Machine SSL certificate"
   checkVECSCert "machine-ssl"

   task "Checking machine certificate"
   checkVECSCert "machine"

   task "Checking vsphere-webclient certificate"
   checkVECSCert "vsphere-webclient"

   if [ $NODE_TYPE != "infrastructure" ]; then   
      task "Checking vpxd certificate"
      checkVECSCert "vpxd"

      task "Checking vpxd-extension certificate"
      checkVECSCert "vpxd-extension"
      
      if [[ "$VC_VERSION" =~ ^7 ]]; then
        task "Checking wcp certificate"
        checkVECSCert "wcp"
        
        task "Checking hvc certificate"
        checkVECSCert "hvc"
      fi

      task "Checking SMS certificate"
      checkVECSCert "SMS"
      
      task "Checking Authentication Proxy certificate"
      checkFilesystemCert "/var/lib/vmware/vmcam/ssl/vmcamcert.pem"
      
      task "Checking Auto Deploy CA certificate"
      checkFilesystemCert "/etc/vmware-rbd/ssl/rbd-ca.crt"
   fi
   
   if checkVECSBackupStore; then
      for alias in $($VECS_CLI entry list --store BACKUP_STORE | grep Alias | awk '{print $NF}'); do
         task "Checking $alias certificate"
         checkVECSCert $alias
      done
   fi
   
   if checkLookupServiceVECSStore; then
      task "Checking legacy Lookup Service certificate"
      checkVECSCert "legacy-lookup-service"
   fi
   
   if [ $NODE_TYPE != "management" ]; then
      if [ -f /usr/lib/vmware-vmdir/share/config/vmdircert.pem ]; then
         task "Checking VMDir certificate"
         checkFilesystemCert "/usr/lib/vmware-vmdir/share/config/vmdircert.pem"
      fi

      task "Checking VMCA certificate"
      checkFilesystemCert "/var/lib/vmware/vmca/root.cer"

      checkSTSTenantCerts
   fi
   
   buildCertificateStatusMessage
   
   if [ ! -z "$CERT_STATUS_MESSAGE" ]; then
      echo $'\n'"${YELLOW}!!! Attention !!!"
      echo "$CERT_STATUS_MESSAGE${NORMAL}"    
   fi
   
   return 0
}

#------------------------------
# Check the SSO domain is configured for Smart Card authentication
#------------------------------
function configuredForCAC() {
   if $LDAP_SEARCH -LLL -h $VMDIR_FQDN -b "cn=ClientCertAuthnTrustedCAs,cn=Default,cn=ClientCertificatePolicies,cn=$SSO_DOMAIN,cn=Tenants,cn=IdentityManager,cn=Services,${VMDIR_DOMAIN_DN}" -D "cn=${VMDIR_USER},cn=users,${VMDIR_DOMAIN_DN}" -y $STAGE_DIR/.vmdir-user-password "(objectclass=*)" userCertificate 2>/dev/null > /dev/null; then
      return 0
   else
      return 1
   fi
}

#------------------------------
# Check if cert is expiring within 30 days
#------------------------------
function checkCertExpireSoon() {
   if ! echo "$1" | openssl x509 -noout -checkend 2592000 2>/dev/null; then
      CERT_END_DATE=$(echo "$1" | openssl x509 -noout -enddate | sed "s/.*=\(.*\)/\1/")
      CERT_END_EPOCH=$(date -d "$CERT_END_DATE" +%s)
      NOW_EPOCH=$(date -d now +%s)
      DAYS_LEFT=$(( (CERT_END_EPOCH - NOW_EPOCH) / 86400))
      
      echo "$DAYS_LEFT"
   else
      echo "-1"
   fi
}

#------------------------------
# Check if cert has recommended Key Usage
#------------------------------
function checkCertKeyUsage() {
   DS_KU=$(echo "$1" | openssl x509 -text -noout 2>/dev/null| grep 'Digital Signature')
   NR_KU=$(echo "$1" | openssl x509 -text -noout 2>/dev/null| grep 'Non Repudiation')
   KE_KU=$(echo "$1" | openssl x509 -text -noout 2>/dev/null| grep 'Key Encipherment')
   
   echo "Checking Key Usage for cert $2" >> $LOG
   echo "Digital Signature search: $DS_KU" >> $LOG
   echo "Non Repudiation search: $NR_KU" >> $LOG
   echo "Key Encipherment search: $KE_KU" >> $LOG
   
   if [[ -z "$DS_KU" || -z "$NR_KU" || -z "$KE_KU" ]]; then
      return 1
   else
      return 0
   fi
}

#------------------------------
# Checks on certificates in VECS
#------------------------------
function checkVECSCert() {
   case $1 in
      machine-ssl)
         STORE="MACHINE_SSL_CERT"
         ALIAS="__MACHINE_CERT"
         CHECK_PNID=1
         CHECK_KU=1
         ;;

      legacy-lookup-service)
         STORE="STS_INTERNAL_SSL_CERT"
         ALIAS="__MACHINE_CERT"
         CHECK_PNID=0
         CHECK_KU=1
         ;;

      SMS)
         STORE="SMS"
         ALIAS="sms_self_signed"
         CHECK_PNID=0
         CHECK_KU=0
         ;;
      
      bkp___MACHINE_CERT|bkp_machine|bkp_vpxd|bkp_vpxd-extension|bkp_vsphere-webclient|bkp_wcp|bkp_hvc)
         STORE="BACKUP_STORE"
         ALIAS=$1
         CHECK_PNID=0
         CHECK_KU=1
         ;;
      
      *)
         STORE=$1
         ALIAS=$1
         CHECK_PNID=0
         CHECK_KU=1
         ;;
   esac

   TEMP_CERT=$($VECS_CLI entry getcert --store $STORE --alias $ALIAS 2>>$LOG)
   
   if [ -z "$TEMP_CERT" ]; then 
      statusMessage "PROBLEM" "RED"
      return 1
   fi

   if echo "$TEMP_CERT" | openssl x509 -noout -checkend 0  2>/dev/null; then
      DAYS_LEFT=$(checkCertExpireSoon "$TEMP_CERT")
      if [[ $DAYS_LEFT -ge 0 ]]; then
         CERT_STATUS_EXPIRES_SOON=1   
         expireSoonMessage "$DAYS_LEFT"
         
         return 0
      else
         if [ $CHECK_PNID = 1 ]; then
            if ! echo "$TEMP_CERT" | openssl x509 -noout -text  2>/dev/null | grep -A1 'Subject Alternative Name' | grep -i "$PNID" > /dev/null; then
               CERT_STATUS_MISSING_PNID=1
               noPnidMessage         
               return 0
            fi
         fi
         if [ $CHECK_KU = 1 ]; then
            if ! checkCertKeyUsage "$TEMP_CERT" "$STORE:$ALIAS"; then
               CERT_STATUS_KEY_USAGE=1
               statusMessage "KEY USAGE" "YELLOW"           
               return 0
            fi             
         fi
         validMessage      
         return 0
      fi
   else
      CERT_STATUS_EXPIRED=1
      expiredMessage      
      return 1
   fi   
}

#------------------------------
# Backup certificate and key from VECS
#------------------------------
function backupVECSCertKey() {
   case $1 in
      machine-ssl)
         VECS_STORE="MACHINE_SSL_CERT"
         VECS_ALIAS="__MACHINE_CERT"
         ;;
      *)
         VECS_STORE=$1
         VECS_ALIAS=$1
         ;;
   esac
   
   if [ "$1" == "machine-ssl" ]; then
      task "Backing up certificate and private key"
   else
      task "$1"
   fi
   $VECS_CLI entry getcert --store $VECS_STORE --alias $VECS_ALIAS > $BACKUP_DIR/$1-$TIMESTAMP.crt 2>>$LOG || errorMessage "Unable to backup $1 certificate"
   $VECS_CLI entry getkey --store $VECS_STORE --alias $VECS_ALIAS > $BACKUP_DIR/$1-$TIMESTAMP.key 2>>$LOG || errorMessage "Unable to backup $1 private key"
   taskMessage "OK" "GREEN"
}

#------------------------------
# Check if certificate has expired
#------------------------------
function checkFilesystemCert() {
   FS_CERT=$(cat $1)
   if echo "$FS_CERT" | openssl x509 -noout -checkend 0 2>/dev/null; then
      DAYS_LEFT=$(checkCertExpireSoon "$FS_CERT")
      if [[ $DAYS_LEFT -gt 0 ]]; then
         CERT_STATUS_EXPIRES_SOON=1   
         expireSoonMessage "$DAYS_LEFT"      
         return 0
      else
         validMessage      
         return 0
      fi
   else
      CERT_STATUS_EXPIRED=1
      expiredMessage      
      return 1
   fi
}

#------------------------------
# Backup certificate and key from filesystem
#------------------------------
function backupFilesystemCertKey() {
   task "Backing up certificate and private key"
   
   if [ -f $1 ]; then
     cp $1 $BACKUP_DIR/$3-$TIMESTAMP.crt >> $LOG 2>&1 || errorMessage "Unable to backup $3 certificate"
   else
      errorMessage "Certificate file $1 does not exist"
   fi
   
   if [ -f $2 ]; then
      cp $2 $BACKUP_DIR/$3-$TIMESTAMP.key >> $LOG 2>&1 || errorMessage "Unable to backup $3 certificate"
   else
      errorMessage "Private key file $2 does not exist"
   fi
   taskMessage "OK" "GREEN"
}

#------------------------------
# Check if certificate is a CA cert
#------------------------------
function isCertCA() {
   if echo "$1" | openssl x509 -noout -text  2>/dev/null | grep 'CA:TRUE' > /dev/null; then
      return 0
   else
      return 1
   fi
}

#------------------------------
# Check if certificate is in DER (binary) format
#------------------------------
function isCertKeyDER() {
   if [ $(file $1 | awk -F':' '{print $NF}' | tr -d ' ') == "data" ]; then
      return 0
   else
      return 1
   fi
}

#------------------------------
# Check if certificate is in the correct format (PEM Base64), and convert if necessary
#------------------------------
function getCorrectCertFormat() {
   if isCertKeyDER $1; then
      if openssl x509 -noout -text -inform der -in $1 > /dev/null 2>&1; then
         openssl x509 -inform der -in $1 -outform pem -out $1-converted.pem
         echo "Converting DER certificate to PEM format: $1-converted.pem" >> $LOG
         echo  "$1-converted.pem"
         return 0
      fi
  
      if openssl pkcs7 -print_certs -inform der -in $1 > /dev/null 2>&1; then 
         openssl pkcs7 -print_certs -inform der -in $1 | grep -vE '^subject|^issuer|^$' > $1-converted.pem
         echo "Converting DER PKCS#7 certificate to PEM mulit-cert format: $1-converted.pem" >> $LOG         
         echo  "$1-converted.pem"
         return 0
      fi         
   else
      if openssl x509 -noout -text -in $1 > /dev/null 2>&1; then
         echo "No conversion necessary for $1" >> $LOG
         echo "$1"
         return 0
      fi
      
      if openssl pkcs7 -print_certs -in $1 > /dev/null 2>&1; then 
         openssl pkcs7 -print_certs -in $1 | grep -vE '^subject|^issuer|^$' > $1-converted.pem
         echo "Converting PKCS#7 certificate to PEM multi-cert format: $1-converted.pem" >> $LOG         
         echo "$1-converted.pem"
         return 0
      fi 
   fi
   echo "Unknown certificate format for $1" >> $LOG
   echo "Unknown format"
   return 0
}

#------------------------------
# Check if private key is in the correct format (PEM Base64), and convert if necessary
#------------------------------
function getCorrectKeyFormat() {
   if isCertKeyDER $1; then
      openssl rsa -inform der -in $1 > $1-converted.key
      echo "Converting private key to PEM format: $1-converted.key" >> $LOG
      echo "$1-converted.key"
   else
      echo "No conversion necessary for $1" >> $LOG
      echo "$1"
   fi
}

#------------------------------
# Check if certificate contains complete CA signing chain
#------------------------------
function checkEmbeddedCAChain() {
   if [ "$(grep 'BEGIN CERTIFICATE' $1 | wc -l)" -gt 1 ]; then
      CHAIN_START=$(grep -n -m2 'BEGIN CERTIFICATE' $1 | tail -n1 | cut -d':' -f1)
      CHECK_CHAIN=$(tail -n+$CHAIN_START $1 > $STAGE_DIR/embedded-root-chain.pem)
      
      if verifyRootChain "$1" "$STAGE_DIR/embedded-root-chain.pem"; then
         echo "$STAGE_DIR/embedded-root-chain.pem"
      else
         echo ""
      fi
   fi
}

#------------------------------
# Get CA chain from certificate file, or by prompt
#------------------------------
function getCAChain() {
   TRUSTED_ROOT_CHAIN=$(checkEmbeddedCAChain "$1")
         
   if [ -z $TRUSTED_ROOT_CHAIN ]; then 
      read -p "Provide path to the Certificate Authority chain: " TRUSTED_ROOT_CHAIN_INPUT
      while [ ! -f "$TRUSTED_ROOT_CHAIN_INPUT" ]; do read -p "${YELLOW}File not found, please provide path to the CA-signed Certificate Authority chain:${NORMAL} " TRUSTED_ROOT_CHAIN_INPUT; done
      TRUSTED_ROOT_CHAIN=$(getCorrectCertFormat "$TRUSTED_ROOT_CHAIN_INPUT")
   fi
}

#------------------------------
# Check if the STS Signing certificates have expired
#------------------------------
function checkSTSTenantCerts() {
   LDAP_CERTS=$($LDAP_SEARCH -LLL -h $VMDIR_FQDN -p 389 -b "cn=$SSO_DOMAIN,cn=Tenants,cn=IdentityManager,cn=Services,$VMDIR_DOMAIN_DN" -D "$VMDIR_MACHINE_ACCOUNT_DN" -y $STAGE_DIR/.machine-account-password '(objectclass=vmwSTSTenantCredential)' userCertificate | grep -vE 'dn:|dc=' | tr -d '\n' | tr -d ' ' | sed 's|userCertificate|\nuserCertificate|g' | grep '^userCertificate' | sed 's|userCertificate::||g')

   TENANT_COUNT=1
   RETURN=0

   for cert in $LDAP_CERTS; do
      TEMP_CERT="-----BEGIN CERTIFICATE-----"$'\n'
      TEMP_CERT+=$(echo $cert | fold -c64)
      TEMP_CERT+=$'\n'"-----END CERTIFICATE-----"

      if echo "$TEMP_CERT" | openssl x509 -text -noout  2>/dev/null | grep 'CA:TRUE' > /dev/null 2>&1; then
         if ! checkSTSTenantCert "${TEMP_CERT}" $TENANT_COUNT "CA"; then RETURN=1; fi
         ((++TENANT_COUNT))         
      else
         if ! checkSTSTenantCert "$TEMP_CERT" $TENANT_COUNT "signing"; then RETURN=1; fi
      fi
   done

   return $RETURN
}

#------------------------------
# Check if individual STS Signing certificate has expired
#------------------------------
function checkSTSTenantCert() {
   task "Checking STS Tenant $2 $3 certificate"

   if echo "$1" | openssl x509 -noout -checkend 0 2>/dev/null; then
      DAYS_LEFT=$(checkCertExpireSoon "$1")
      if [[ $DAYS_LEFT -gt 0 ]]; then
         CERT_STATUS_EXPIRES_SOON=1
         expireSoonMessage "$DAYS_LEFT"      
         return 0
      else
         HAS_KEY_USAGE=$(checkCertKeyUsage "$1" "STS Tenant $2 $3")
         if [[ $3 == "signing" && $HAS_KEY_USAGE -gt 0 ]]; then
            CERT_STATUS_KEY_USAGE=1      
            statusMessage "KEY USAGE" "YELLOW"          
            return 0
         fi
         validMessage      
         return 0
      fi
   else
      CERT_STATUS_EXPIRED=1
      expiredMessage      
      return 1
   fi 
}

#------------------------------
# Check CA certificates in VMDir and VECS
#------------------------------
function checkCACertificates() {
   VMDIR_CERTS=()
   VMDIR_CERT_SKIDS=()
   VECS_CERTS=()
   VECS_CERT_ALIASES=()
   printf "\n\n"
   header "Check CA certificates in VMDir [by CN(id)]"
   for skid in $($DIR_CLI trustedcert list --login $VMDIR_USER --password "$(cat $STAGE_DIR/.vmdir-user-password)" | grep '^CN' | tr -d '\t' | awk -F':' '{print $2}'); do
      echo "Retrieving certificate with Subject Key ID $skid from VMDir" >> $LOG
      $DIR_CLI trustedcert get --id $skid --outcert $STAGE_DIR/$skid.crt --login $VMDIR_USER --password "$(cat $STAGE_DIR/.vmdir-user-password)" 2>&1 >> $LOG
        
      task "${skid}"
      CA_CERT=$(cat $STAGE_DIR/$skid.crt)
      if ! openssl x509 -noout -checkend 0 -in $STAGE_DIR/$skid.crt 2>/dev/null; then
         CERT_STATUS_EXPIRED=1
         statusMessage "EXPIRED" "YELLOW"
      elif ! isCertCA "$(cat $STAGE_DIR/$skid.crt)"; then
         CERT_STATUS_NON_CA=1
         statusMessage "NON-CA" "YELLOW"
      else         
         DAYS_LEFT=$(checkCertExpireSoon "$CA_CERT")
         if [[ $DAYS_LEFT -gt 0 ]]; then
            CERT_STATUS_EXPIRES_SOON=1       
            expireSoonMessage "$DAYS_LEFT"
         else     
            statusMessage "VALID" "GREEN"
         fi
      fi
      VMDIR_CA_CERT_SUBJECT=$(echo "$CA_CERT" | openssl x509 -noout -subject 2>/dev/null | sed 's/subject= //')
      VMDIR_CA_CERT_ENDDATE=$(echo "$CA_CERT" | openssl x509 -noout -enddate 2>/dev/null | awk -F'=' '{print $NF}')
      VMDIR_CA_CERT_SKID=$(echo "$CA_CERT" | openssl x509 -noout -text 2>/dev/null | grep -A1 'Subject Key' | tail -n1 | tr -d '[:space:]')
      VMDIR_CA_CERT_INFO="Subject: $VMDIR_CA_CERT_SUBJECT"
      VMDIR_CA_CERT_INFO+=$'\n'"    End Date: $VMDIR_CA_CERT_ENDDATE"
      VMDIR_CA_CERT_INFO+=$'\n'"    Subject Key ID: $VMDIR_CA_CERT_SKID"
      if isCertCA "$CA_CERT"; then 
         VMDIR_CA_CERT_INFO+=$'\n'"    Is CA cert: Yes"
      else 
         VMDIR_CA_CERT_INFO+=$'\n'"    Is CA cert: No"
      fi
      VMDIR_CERTS+=("$VMDIR_CA_CERT_INFO")
      VMDIR_CA_CERT_SKIDS+=($skid)
   done
   
   header "Check CA certificates in VECS [by Alias]"
   IFS=$'\n'
   for alias in $($VECS_CLI entry list --store TRUSTED_ROOTS --text | grep '^Alias' | tr -d '\t' | awk -F':' '{print $2}'); do
      echo "Checking certificate with alias '$alias'" >> $LOG
      TEMP_VECS_CERT=$($VECS_CLI entry getcert --store TRUSTED_ROOTS --alias "$alias")
      
      task $alias
      
      if ! echo "$TEMP_VECS_CERT" | openssl x509 -noout -checkend 0 2>/dev/null; then
         CERT_STATUS_EXPIRED=1
         statusMessage "EXPIRED" "YELLOW"
      elif ! echo "$TEMP_VECS_CERT" | openssl x509 -text -noout 2>/dev/null | grep 'CA:TRUE' > /dev/null; then
         CERT_STATUS_NON_CA=1
         statusMessage "NON-CA" "YELLOW"
      elif [ $(echo "$TEMP_VECS_CERT" | openssl x509 -fingerprint -sha1 -noout | cut -d '=' -f 2 | tr -d ':' | awk '{print tolower($0)}') != "$alias" ]; then
         CERT_STATUS_BAD_ALIAS=1
         statusMessage "BAD ALIAS" "YELLOW"
      else
         DAYS_LEFT=$(checkCertExpireSoon "$TEMP_VECS_CERT")
         if [[ $DAYS_LEFT -gt 0 ]]; then
            CERT_STATUS_EXPIRES_SOON=1       
            expireSoonMessage "$DAYS_LEFT"
         else
            statusMessage "VALID" "GREEN"
         fi
      fi
      VECS_CA_CERT_SUBJECT=$(echo "$TEMP_VECS_CERT" | openssl x509 -noout -subject 2>/dev/null | sed 's/subject= //')
      VECS_CA_CERT_ENDDATE=$(echo "$TEMP_VECS_CERT" | openssl x509 -noout -enddate 2>/dev/null | awk -F'=' '{print $NF}')
      VECS_CA_CERT_SKID=$(echo "$TEMP_VECS_CERT" | openssl x509 -noout -text 2>/dev/null | grep -A1 'Subject Key' | tail -n1 | tr -d '[:space:]')
      VECS_CA_CERT_INFO="Alias: $alias"
      VECS_CA_CERT_INFO+=$'\n'"    Subject: $VECS_CA_CERT_SUBJECT"
      VECS_CA_CERT_INFO+=$'\n'"    End Date: $VECS_CA_CERT_ENDDATE"
      VECS_CA_CERT_INFO+=$'\n'"    Subject Key ID: $VECS_CA_CERT_SKID"
      if isCertCA "$TEMP_VECS_CERT"; then 
         VECS_CA_CERT_INFO+=$'\n'"    Is CA cert: Yes"
      else 
         VECS_CA_CERT_INFO+=$'\n'"    Is CA cert: No"
      fi
      
      VECS_CERTS+=("$VECS_CA_CERT_INFO")
      VECS_CA_CERT_ALIASES+=($alias)
   done
   unset IFS
   
   header "Manage CA Certificates"
   echo " 1. Manage CA certificates in VMware Directory" | tee -a $LOG
   echo " 2. Manage CA certificates in VECS" | tee -a $LOG
   echo " R. Return to Main Menu" | tee -a $LOG
   
   read -p $'\n'"Select an option [R]: " MANAGE_CA_OPTION_INPUT
   
   if [ -z "${MANAGE_CA_OPTION_INPUT}" ]; then 
      MANAGE_CA_OPTION="R"
   else
      MANAGE_CA_OPTION=$MANAGE_CA_OPTION_INPUT
   fi
   
   case $MANAGE_CA_OPTION in
      1)
      manageCACertsVMDir
      ;;
      
      2)
      manageCACertsVECS
      ;;
   esac
}

#------------------------------
# Manage CA certificates in VMDir
#------------------------------
function manageCACertsVMDir() {
   header "Manage CA Certificates in VMware Directory"
   i=0
   while [ $i -lt "${#VMDIR_CERTS[@]}" ]; do
      n=$((i+1))
      printf "%2s. %s\n\n" $n "${VMDIR_CERTS[$i]}"
      ((++i))
   done

   
   read -p $'\n'"Enter the number(s) of the certificate(s) to delete (multiple entries separated by a comma): " DELETE_VMDIR_CA_LIST
   
   if [ ! -z $DELETE_VMDIR_CA_LIST ]; then
      header "Removing CA certificates from VMware Directory"
      for index in $(echo $DELETE_VMDIR_CA_LIST | sed 's/,/ /g'); do
         skid=${VMDIR_CA_CERT_SKIDS[$((index - 1))]}
         task "Backing up $skid"
         if $DIR_CLI trustedcert get --id $skid --login $VMDIR_USER --password "$(cat $STAGE_DIR/.vmdir-user-password)" --outcert $BACKUP_DIR/$skid.crt 2>&1 >> $LOG; then
            taskMessage "OK" "GREEN"
         else
            errorMessage "Unable to backup certificate with Subject Key ID $skid"
         fi
         
         task "Removing $skid"
         if $DIR_CLI trustedcert unpublish --cert $BACKUP_DIR/$skid.crt --login $VMDIR_USER --password "$(cat $STAGE_DIR/.vmdir-user-password)" 2>&1 >> $LOG; then
            taskMessage "OK" "GREEN"
         else
            errorMessage "Unable to unpublish certificate with Subject Key ID $skid"
         fi
      done
      task "Refreshing CA certificates to VECS"
      if $VECS_CLI force-refresh 2>&1 >> $LOG; then
         taskMessage "OK" "GREEN"
      else
         errorMessage "Error refreshing CA certificates to VECS"
      fi
   fi
}

#------------------------------
# Manage CA certificates in VECS
#------------------------------
function manageCACertsVECS() {
   header "Manage CA Certificates in VECS"
   i=0
   while [ $i -lt "${#VECS_CERTS[@]}" ]; do
      n=$((i+1))
      printf "%2s. %s\n\n" $n "${VECS_CERTS[$i]}"
      ((++i))
   done
   
   read -p $'\n'"Enter the number(s) of the certificate(s) to delete (multiple entries separated by a comma): " DELETE_VECS_CA_LIST
   
   if [ ! -z $DELETE_VECS_CA_LIST ]; then
      header "Removing CA certificates from VECS"
      for index in $(echo $DELETE_VECS_CA_LIST | sed 's/,/ /g'); do
         alias=${VECS_CA_CERT_ALIASES[$((index - 1))]}
         alias_file=$(echo "$alias" | sed 's/ /_/g')
         task "Backing up $alias"
         if $VECS_CLI entry getcert --store TRUSTED_ROOTS --alias "$alias" > $BACKUP_DIR/${alias_file}.crt 2>&1 >> $LOG; then
            taskMessage "OK" "GREEN"
         else
            errorMessage "Unable to backup certificate with alias '$alias'"
         fi
         
         task "Removing $alias"
         if [[ "$VC_VERSION" =~ ^7 ]]; then
            # you can no longer add/delete certificates from the TRUSTED_ROOT store using vecs-cli in 7.x
            # we must remove the entries from the AFD database directly
            AFD_TRUSTED_ROOTS_STORE_ID=$(sqlite3 /storage/db/vmware-vmafd/afd.db "SELECT StoreID FROM StoreTable WHERE StoreName='TRUSTED_ROOTS'")
            AFD_BACKUP_FILE="afd.db-$(date +%Y%m%d)"
            
            if [ ! -f $BACKUP_DIR/$AFD_BACKUP_FILE ]; then
               cp /storage/db/vmware-vmafd/afd.db $BACKUP_DIR/$AFD_BACKUP_FILE
            fi
            
            if sqlite3 /storage/db/vmware-vmafd/afd.db "DELETE FROM CertTable WHERE StoreID='$AFD_TRUSTED_ROOTS_STORE_ID' AND Alias='$alias'"; then
               taskMessage "OK" "GREEN"
            else
               errorMessage "Unable to remove certificate with alias '$alias' from the AFD database"
            fi
         else
            if $VECS_CLI entry delete --store TRUSTED_ROOTS --alias "$alias" -y 2>&1 >> $LOG; then
               taskMessage "OK" "GREEN"
            else
               errorMessage "Unable to unpublish certificate with alias '$alias'"
            fi
         fi
      done
   fi
}

#------------------------------
# View certificate info
#------------------------------
function viewCertificateInfo() {
   echo "$1" | openssl x509 -text -noout -fingerprint -sha1 2>/dev/null
   
   return 0
}

#------------------------------
# View CRL info
#------------------------------
function viewCRLInfo() {
   echo "$1" | openssl crl -text -noout 2>/dev/null
}

#------------------------------
# Extra information regarding the Machine SSL certificate
#------------------------------
function checkCurrentMachineSSLUsage() {
   RHTTPPROXY_CERT_FINGERPRINT=$(echo | openssl s_client -connect localhost:443 2>/dev/null | openssl x509 -noout -fingerprint -sha1 2>/dev/null | awk -F'=' '{print $NF}')
   VPXD_CERT_FINGERPRINT=$(echo | openssl s_client -connect localhost:8089 2>/dev/null | openssl x509 -noout -fingerprint -sha1 2>/dev/null | awk -F'=' '{print $NF}')
   reportLine "               |_Current certificate used by the reverse proxy: $RHTTPPROXY_CERT_FINGERPRINT" | tee -a $REPORT
   reportLine "               |_Current certificate used by vCenter (vpxd)   : $VPXD_CERT_FINGERPRINT" | tee -a $REPORT
}

#------------------------------
# Extra information regarding the vpxd-extension certificate
#------------------------------
function checkCurrentExtensionThumbprints() {
   EAM_EXT_FINGERPRINT=$($PSQL -d VCDB -U postgres -c "SELECT thumbprint FROM vpx_ext WHERE ext_id = 'com.vmware.vim.eam'" -t | grep -v '^$' | tr -d ' ')
   RBD_EXT_FINGERPRINT=$($PSQL -d VCDB -U postgres -c "SELECT thumbprint FROM vpx_ext WHERE ext_id = 'com.vmware.rbd'" -t | grep -v '^$' | tr -d ' ')
   VUM_EXT_FINGERPRINT=$($PSQL -d VCDB -U postgres -c "SELECT thumbprint FROM vpx_ext WHERE ext_id = 'com.vmware.vcIntegrity'" -t | grep -v '^$' | tr -d ' ')
   IMAGE_BUILDER_EXT_FINGERPRINT=$($PSQL -d VCDB -U postgres -c "SELECT thumbprint FROM vpx_ext WHERE ext_id = 'com.vmware.imagebuilder'" -t | grep -v '^$' | tr -d ' ')
   reportLine "               |_Thumbprints in VCDB for extensions that should use the vpxd-extension certificate" | tee -a ${REPORT}
   reportLine "                  |_com.vmware.vim.eam     : $EAM_EXT_FINGERPRINT" | tee -a $REPORT
   reportLine "                  |_com.vmware.rbd         : $RBD_EXT_FINGERPRINT" | tee -a $REPORT
   reportLine "                  |_com.vmware.vcIntegrity : $VUM_EXT_FINGERPRINT" | tee -a $REPORT
   
   if [ ! -z $IMAGE_BUILDER_EXT_FINGERPRINT ]; then
      reportLine "                  |_com.vmware.imagebuilder: $IMAGE_BUILDER_EXT_FINGERPRINT" | tee -a $REPORT
   fi
}

#------------------------------
# Generate certificate report
#------------------------------
function generateCertificateReport() {
   disableColor
   CERT_MGMT_MODE=$($PSQL -d VCDB -U postgres -c "SELECT value FROM vpx_parameter WHERE name='vpxd.certmgmt.mode'" -t | grep -v '^$')
   printf '%0.1s' "="{1..130} | tee $REPORT
   printf '\n' | tee -a $REPORT
   echo "SSL Certificate Report" | tee -a $REPORT
   echo "Host: $HOSTNAME" | tee -a $REPORT
   echo "Date: $(date -u)" | tee -a $REPORT
   echo "Node Type: $NODE_TYPE" | tee -a $REPORT
   echo "Machine ID: $MACHINE_ID" | tee -a $REPORT
   if [ $NODE_TYPE != "infrastructure" ]; then
      echo "Certificate Management Mode: $CERT_MGMT_MODE" | tee -a $REPORT
   fi
   printf '%0.1s' "="{1..130} | tee -a $REPORT
   printf '\n' | tee -a $REPORT
   
   VMDIR_CA_SUBJECT_IDS=""
   VECS_CA_SUBJECT_IDS=""
   for CNID in $($DIR_CLI trustedcert list --login "$VMDIR_USER_UPN" --password "$VMDIR_USER_PASSWORD" | grep 'CN(id)' | awk '{print $NF}'); do
      CERT=$($DIR_CLI trustedcert get --id $CNID --login "$VMDIR_USER_UPN" --password "$VMDIR_USER_PASSWORD" --outcert /dev/stdout)
      VMDIR_CERT_INFO=$(viewCertificateInfo "$CERT")
      
      VMDIR_CERT_SERIAL=$(echo "$VMDIR_CERT_INFO" | grep -A1 'Serial Number' | tail -n1 | tr -d ' ' | awk '{print toupper($0)}')
      VMDIR_CERT_SUBJECT=$(echo "$VMDIR_CERT_INFO" | grep 'Subject: ' | sed 's/Subject: //')
      VMDIR_CERT_SUBJECT_KEY=$(echo "$VMDIR_CERT_INFO" | grep -A1 'Subject Key Identifier' | tail -n1 | tr -d ' ')
      VMDIR_CA_SUBJECT_IDS+="serial:$VMDIR_CERT_SERIAL|DirName:$VMDIR_CERT_SUBJECT|keyid:$VMDIR_CERT_SUBJECT_KEY"$'\n'
   done
   
   IFS=$'\n'
   for alias in $($VECS_CLI entry list --store TRUSTED_ROOTS --text | grep 'Alias' | awk -F':' '{print $NF}' | tr -d '\t'); do
      CERT=$($VECS_CLI entry getcert --store TRUSTED_ROOTS --alias "$alias")
      VECS_CERT_INFO=$(viewCertificateInfo "$CERT")
      
      VECS_CERT_SERIAL=$(echo "$VECS_CERT_INFO" | grep -A1 'Serial Number' | tail -n1 | tr -d ' ' | awk '{print toupper($0)}')
      VECS_CERT_SUBJECT=$(echo "$VECS_CERT_INFO" | grep 'Subject: ' | sed 's/Subject: //')
      VECS_CERT_SUBJECT_KEY=$(echo "$VECS_CERT_INFO" | grep -A1 'Subject Key Identifier' | tail -n1 | tr -d ' ')
      VECS_CA_SUBJECT_IDS+="serial:$VECS_CERT_SERIAL|DirName:$VECS_CERT_SUBJECT|keyid:$VECS_CERT_SUBJECT_KEY"$'\n'
   done
   unset IFS
   
   reportLine "VECS Certificates" | tee -a $REPORT
   
   for store in $($VECS_CLI store list); do
      reportLine "   Store: $store" | tee -a $REPORT
      IFS=$'\n'
      for alias in $($VECS_CLI entry list --store $store --text | grep 'Alias' | tr -d '\t' | awk -F':' '{print $NF}'); do
         reportLine "      Alias: $alias" | tee -a $REPORT
         VECS_HASH=$($VECS_CLI entry getcert --store $store --alias "$alias" 2>/dev/null)
         if [[ $? -eq 0 ]]; then
            if ! echo "$VECS_HASH" | head -n1 | grep "BEGIN CERTIFICATE" > /dev/null; then
               reportCRLDetails "$VECS_HASH"
            else
               case $store-$alias in
                  MACHINE_SSL_CERT-__MACHINE_CERT)
                     EXTRA_INFO="checkCurrentMachineSSLUsage"
                  ;;
                  
                  vpxd-extension-vpxd-extension)
                     EXTRA_INFO="checkCurrentExtensionThumbprints"
                  ;;
                  
                  *)
                     EXTRA_INFO=""
                  ;;
               esac
               
               reportCertDetails "$VECS_HASH" "$EXTRA_INFO"
            fi
         else
            reportLine "         |_No certificate found in store" | tee -a $REPORT
         fi
      done
      unset IFS
   done
   
   reportLine "VMware Directory Certificates" | tee -a $REPORT
   reportLine "   CA Certificates" | tee -a $REPORT
   
   for CNID in $($DIR_CLI trustedcert list --login "$VMDIR_USER_UPN" --password "$VMDIR_USER_PASSWORD" | grep 'CN(id)' | awk '{print $NF}'); do
      reportLine "      CN(id): $CNID" | tee -a $REPORT
      VMDIR_CA_HASH=$($DIR_CLI trustedcert get --id $CNID --login "$VMDIR_USER_UPN" --password "$VMDIR_USER_PASSWORD" --outcert /dev/stdout)
      reportCertDetails "$VMDIR_CA_HASH"
   done
   
   reportLine "   Service Principal (Solution User) Certificates" | tee -a $REPORT
   
   for hash in $($LDAP_SEARCH -LLL -h $VMDIR_FQDN -b  "cn=ServicePrincipals,$VMDIR_DOMAIN_DN" -D "cn=$VMDIR_USER,cn=users,$VMDIR_DOMAIN_DN" -y $STAGE_DIR/.vmdir-user-password "(objectclass=vmwServicePrincipal)" userCertificate | tr -d '\n' | tr -d ' '| sed -e 's/dn:/\n&/g' -e 's/userCertificate::/\n&/g' | grep '^userCertificate' | sed 's/userCertificate:://g'); do
      TEMP_CERT="-----BEGIN CERTIFICATE-----"$'\n'
      TEMP_CERT+=$(echo "$hash" | fold -c64)
      TEMP_CERT+=$'\n'"-----END CERTIFICATE-----"
      SERVICE_PRINCIPAL=$(echo "$TEMP_CERT" | openssl x509 -noout -text 2>/dev/null | grep 'Subject:' | awk -F'CN=' '{print $2}' | awk -F',' '{print $1}')
      reportLine "      Service Principal: $SERVICE_PRINCIPAL" | tee -a $REPORT
      reportCertDetails "$TEMP_CERT"
   done
   
   reportLine "   Single Sign-On Secure Token Service Certificates" | tee -a $REPORT
   TENANT_COUNT=0
   TENANT_CA_COUNT=1
   for hash in $($LDAP_SEARCH -LLL -h $VMDIR_FQDN -b  "cn=$SSO_DOMAIN,cn=Tenants,cn=IdentityManager,cn=Services,$VMDIR_DOMAIN_DN" -D "cn=$VMDIR_USER,cn=users,$VMDIR_DOMAIN_DN" -y $STAGE_DIR/.vmdir-user-password "(objectclass=vmwSTSTenantCredential)" userCertificate | tr -d '\n' | tr -d ' '| sed -e 's/dn:/\n&/g' -e 's/userCertificate::/\n&/g' | grep '^userCertificate' | sed 's/userCertificate:://g'); do
      TEMP_CERT="-----BEGIN CERTIFICATE-----"$'\n'
      TEMP_CERT+=$(echo "$hash" | fold -c64)
      TEMP_CERT+=$'\n'"-----END CERTIFICATE-----"
      
      if isCertCA "$TEMP_CERT"; then
         reportLine "      TenantCredential-$TENANT_COUNT CA Certificate" | tee -a $REPORT
         ((++TENANT_CA_COUNT))
      else
         ((++TENANT_COUNT))
         reportLine "      TenantCredential-$TENANT_COUNT Signing Certificate" | tee -a $REPORT  
      fi
      reportCertDetails "$TEMP_CERT"
   done
   
   CAC_CAS=$($LDAP_SEARCH -LLL -h $VMDIR_FQDN -b "cn=DefaultClientCertCAStore,cn=ClientCertAuthnTrustedCAs,cn=Default,cn=ClientCertificatePolicies,cn=$SSO_DOMAIN,cn=Tenants,cn=IdentityManager,cn=Services,$VMDIR_DOMAIN_DN" -D "cn=$VMDIR_USER,cn=users,$VMDIR_DOMAIN_DN" -y $STAGE_DIR/.vmdir-user-password "(objectclass=vmwSTSTenantTrustedCertificateChain)" userCertificate 2>/dev/null | tr -d '\n' | tr -d ' '| sed -e 's/dn:/\n&/g' -e 's/userCertificate::/\n&/g' | grep '^userCertificate' | sed 's/userCertificate:://g')
   
   if [ -n "$CAC_CAS" ]; then
      CAC_ISSUING_CA_COUNT=1
      reportLine "   Smart Card Issuing CA Certificates" | tee -a $REPORT
      for hash in $CAC_CAS; do
         TEMP_CERT="-----BEGIN CERTIFICATE-----"$'\n'
         TEMP_CERT+=$(echo "$hash" | fold -c64)
         TEMP_CERT+=$'\n'"-----END CERTIFICATE-----"      
         reportLine "      Smart Card Issuing CA $CAC_ISSUING_CA_COUNT" | tee -a $REPORT
         reportCertDetails "$TEMP_CERT"
         ((++CAC_ISSUING_CA_COUNT))
      done
   fi
   
   AD_LDAPS_CERTS=$($LDAP_SEARCH -LLL -h $VMDIR_FQDN -b "cn=IdentityProviders,cn=$SSO_DOMAIN,cn=Tenants,cn=IdentityManager,cn=Services,$VMDIR_DOMAIN_DN" -D "cn=$VMDIR_USER,cn=users,$VMDIR_DOMAIN_DN" -y $STAGE_DIR/.vmdir-user-password "(vmwSTSProviderType=IDENTITY_STORE_TYPE_LDAP_WITH_AD_MAPPING)" userCertificate 2>/dev/null | tr -d '\n' | tr -d ' ' | sed -e 's/dn:/\n&/g' -e 's/userCertificate::/\n&/g' -e 's/vmwSTSPassword:/\n&/g' | grep '^userCertificate::' | sed 's/userCertificate:://g')
   
   if [ -n "$AD_LDAPS_CERTS" ]; then
      reportLine "   AD Over LDAPS Domain Controller Certificates" | tee -a $REPORT
      LDAPS_DC_CERT_COUNT=1
      for hash in $AD_LDAPS_CERTS; do
         TEMP_CERT="-----BEGIN CERTIFICATE-----"$'\n'
         TEMP_CERT+=$(echo "$hash" | fold -c64)
         TEMP_CERT+=$'\n'"-----END CERTIFICATE-----"      
         reportLine "      Domain Controller Certificate $LDAPS_DC_CERT_COUNT" | tee -a $REPORT
         reportCertDetails "$TEMP_CERT"
         ((++LDAPS_DC_CERT_COUNT))
      done
   fi
   
   reportLine "Filesystem Certificates" | tee -a $REPORT
   if [ "${NODE_TYPE}" != "management" ]; then
      reportLine "   Authentication Proxy Certificate" | tee -a $REPORT
      reportLine "      Certificate: /var/lib/vmware/vmcam/ssl/vmcamcert.pem" | tee -a $REPORT
      AUTH_PROXY_CERT=$(cat /var/lib/vmware/vmcam/ssl/vmcamcert.pem)
      reportCertDetails "$AUTH_PROXY_CERT"
   fi
   if [ "$NODE_TYPE" != "management" ]; then
      reportLine "   VMware Directory Certificate" | tee -a $REPORT
      reportLine "      Certificate: /usr/lib/vmware-vmdir/share/config/vmdircert.pem" | tee -a $REPORT
      VMDIR_CERT=$(cat /usr/lib/vmware-vmdir/share/config/vmdircert.pem)
      reportCertDetails "$VMDIR_CERT"
      
      reportLine "   VMCA Certificate" | tee -a $REPORT
      reportLine "      Certificate: /var/lib/vmware/vmca/root.cer" | tee -a $REPORT
      VMCA_CERT=$(cat /var/lib/vmware/vmca/root.cer)
      reportCertDetails "$VMCA_CERT"
   fi
   if [ "$NODE_TYPE" != "infrastructure" ]; then
      reportLine "   Auto Deploy CA Certificate" | tee -a $REPORT
      reportLine "      Certificate: /etc/vmware-rbd/ssl/rbd-ca.crt" | tee -a $REPORT
      AUTO_DEPLOY_CA_CERT=$(cat /etc/vmware-rbd/ssl/rbd-ca.crt)
      reportCertDetails "$AUTO_DEPLOY_CA_CERT"
   fi
   
   if grep '<clientCAListFile>' /etc/vmware-rhttpproxy/config.xml | grep -v '<!--' > /dev/null; then
      reportLine "   Smart Card Whitelist Certificates" | tee -a $REPORT
      CAC_WHITELIST_PEM=$(grep '<clientCAListFile>' /etc/vmware-rhttpproxy/config.xml | grep -v '<!--' | awk -F'>' '{print $2}' | awk -F'<' '{print $1}')
      csplit -s -z -f $STAGE_DIR/cac_whitelist_ca- -b %02d.crt $CAC_WHITELIST_PEM "/-----BEGIN CERTIFICATE-----/" "{*}"
      WHITELIST_CERT_COUNT=1
      for cert in $(ls $STAGE_DIR/cac_whitelist_ca-*); do
         reportLine "      Certificate $WHITELIST_CERT_COUNT: $CAC_WHITELIST_PEM" | tee -a $REPORT  
         WHITELIST_CERT=$(cat $cert)
         reportCertDetails "$WHITELIST_CERT"
         ((++WHITELIST_CERT_COUNT))
      done
   fi
   
   reportLine "Lookup Service Registration Trust Anchors" | tee -a $REPORT
   CERT_HASHES=()
   CERT_COUNT=1
   
   $LDAP_SEARCH -LLL -h $VMDIR_FQDN -p 389 -b "cn=Sites,cn=Configuration,$VMDIR_DOMAIN_DN" -D "cn=$VMDIR_USER,cn=users,$VMDIR_DOMAIN_DN" -y $STAGE_DIR/.vmdir-user-password "(|(objectclass=vmwLKUPEndpointRegistration)(objectclass=vmwLKUPServiceEndpoint))" vmwLKUPEndpointSslTrust vmwLKUPSslTrustAnchor vmwLKUPURI > $STAGE_DIR/trust-anchors.raw

   TRUST_ANCHORS=$(cat $STAGE_DIR/trust-anchors.raw | tr -d '\n' | tr -d ' ' | sed -e 's|vmwLKUPEndpointSslTrust|\nvmwLKUPEndpointSslTrust|g' -e 's|vmwLKUPSslTrustAnchor|\nvmwLKUPSslTrustAnchor|g' -e 's|vmwLKUPURI|\nvmwLKUPURI|g' -e 's|dn:|\ndn:|g'| grep -vE '^dn:|^vmwLKUPURI' | grep '^vmwLKUP' | sed -e 's|vmwLKUPEndpointSslTrust||g' -e 's|vmwLKUPSslTrustAnchor||g' -e 's|:||g' | sort | uniq)
   
   for cert in $TRUST_ANCHORS; do 
      if [[ "$cert" =~ ^TUl ]]; then
         CURRENT_CERT=$(echo $cert | base64 --decode | tr -d '\r\n')
      else
         CURRENT_CERT=($cert)
      fi
      if [[ ! "${CERT_HASHES[@]}" =~ "$CURRENT_CERT" ]]; then
         CERT_HASHES+=($CURRENT_CERT)
      fi
   done

   for hash in "${CERT_HASHES[@]}"; do
      reportLine "      Endpoint Certificate $CERT_COUNT" | tee -a $REPORT
      TEMP_CERT="-----BEGIN CERTIFICATE-----"$'\n'
      TEMP_CERT+=$(echo $hash | fold -c64)
      TEMP_CERT+=$'\n'"-----END CERTIFICATE-----"
      
      double_encoded_hash=$(echo "$hash" | tr -d '\n' | sed -e 's/.\{76\}/&\r\n/g' | xargs -0 printf "%s\r\n" | base64 -w 0)     
      
      USED_BY_SERVICE_IDS=$(cat $STAGE_DIR/trust-anchors.raw | tr -d '\n' | tr -d ' ' | sed -e 's|vmwLKUPEndpointSslTrust|\nvmwLKUPEndpointSslTrust|g' -e 's|vmwLKUPSslTrustAnchor|\nvmwLKUPSslTrustAnchor|g' -e 's|dn:|\ndn:|g'| grep -B1 ${hash} | grep '^dn:' | awk -F',' '{print $2}' | tr -d 'cn=' | sort | uniq)
      USED_BY_SERVICE_IDS+=$'\n'$(cat $STAGE_DIR/trust-anchors.raw | tr -d '\n' | tr -d ' ' | sed -e 's|vmwLKUPEndpointSslTrust|\nvmwLKUPEndpointSslTrust|g' -e 's|vmwLKUPSslTrustAnchor|\nvmwLKUPSslTrustAnchor|g' -e 's|dn:|\ndn:|g'| grep -B1 $double_encoded_hash | grep '^dn:' | awk -F',' '{print $2}' | tr -d 'cn=' | sort | uniq | xargs -0 printf "\n%s")
      NUM_USED_BY_SERVICE_IDS=$(echo "$USED_BY_SERVICE_IDS" | grep -v '^$' | wc -l)

      USED_BY_ENDPOINTS=$(cat $STAGE_DIR/trust-anchors.raw | tr -d '\n' | tr -d ' ' | sed -e 's|vmwLKUPEndpointSslTrust|\nvmwLKUPEndpointSslTrust|g' -e 's|vmwLKUPSslTrustAnchor|\nvmwLKUPSslTrustAnchor|g' -e 's|vmwLKUPURI|\nvmwLKUPURI|g' -e 's|dn:|\ndn:|g' | grep -v '^dn:' | grep -B1 ${hash} | grep '^vmwLKUPURI' | sed -e 's/vmwLKUPURI://g' | sort | uniq)              
      USED_BY_ENDPOINTS+=$'\n'$(cat $STAGE_DIR/trust-anchors.raw | tr -d '\n' | tr -d ' ' | sed -e 's|vmwLKUPEndpointSslTrust|\nvmwLKUPEndpointSslTrust|g' -e 's|vmwLKUPSslTrustAnchor|\nvmwLKUPSslTrustAnchor|g' -e 's|vmwLKUPURI|\nvmwLKUPURI|g' -e 's|dn:|\ndn:|g' | grep -v '^dn:' | grep -B1 $double_encoded_hash | grep '^vmwLKUPURI' | sed -e 's/vmwLKUPURI://g' | sort | uniq)   
      NUM_USED_BY_ENDPOINTS=$(echo "$USED_BY_ENDPOINTS" | grep -v '^$' | wc -l)

      ((++CERT_COUNT))
      
      reportTrustAnchorDetails "$TEMP_CERT" "$USED_BY_SERVICE_IDS" "$USED_BY_ENDPOINTS"
   done
   enableColor
   
   echo $'\n'"${YELLOW}Certificate report is available at ${REPORT}${NORMAL}"$'\n'
}

#------------------------------
# CRL information for report
#------------------------------
function reportCRLDetails() {
   REPORT_CRL=$1
   REPORT_CRL_INFO=$(viewCRLInfo "$REPORT_CRL")
   REPORT_CRL_ISSUER=$(echo "$REPORT_CRL_INFO" | grep 'Issuer:' | awk -F'Issuer: ' '{print $NF}')
   REPORT_CRL_LAST_UPDATE=$(echo "$REPORT_CRL" | openssl crl -noout -lastupdate 2>/dev/null | sed 's/lastUpdate=//')
   REPORT_CRL_NEXT_UPDATE=$(echo "$REPORT_CRL" | openssl crl -noout -nextupdate 2>/dev/null | sed 's/nextUpdate=//')
   REPORT_CRL_SIGNATURE_ALGORITHM=$(echo "$REPORT_CRL_INFO" | grep 'Signature Algorithm' | head -n1 | awk '{print $NF}')
   REPORT_CRL_AUTH_KEYS=$(echo "$REPORT_CRL_INFO" | grep 'Authority Key Identifier' -A3 | grep -E 'keyid:|DirName:|issuer:' | tr -d ' ')
   
   reportLine "         Issuer: $REPORT_CRL_ISSUER" | tee -a $REPORT
   reportLine "            Last Update: $REPORT_CRL_LAST_UPDATE" | tee -a $REPORT
   reportLine "            Next Update: $REPORT_CRL_NEXT_UPDATE" | tee -a $REPORT
   reportLine "            Signature Algorithm: $REPORT_CRL_SIGNATURE_ALGORITHM" | tee -a $REPORT
}

#------------------------------
# Certificate information for report
#------------------------------
function reportCertDetails() {
   ISSUER_FOUND_VMDIR=0
   ISSUER_FOUND_VECS=0
   REPORT_CERT=${1}
   if isCertCA "$REPORT_CERT"; then REPORT_CERT_IS_CA="Yes"; else REPORT_CERT_IS_CA="No"; fi
   REPORT_CERT_INFO=$(viewCertificateInfo "$REPORT_CERT")
   REPORT_CERT_SUBJECT=$(echo "$REPORT_CERT_INFO" | grep 'Subject:' | awk -F'Subject: ' '{print $NF}')
   REPORT_CERT_ISSUER=$(echo "$REPORT_CERT_INFO" | grep 'Issuer:' | awk -F'Issuer: ' '{print $NF}')
   REPORT_CERT_VALID_START=$(echo "$REPORT_CERT" | openssl x509 -noout -startdate 2>/dev/null | sed 's/notBefore=//')
   REPORT_CERT_VALID_END=$(echo "$REPORT_CERT" | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//')
   REPORT_CERT_FINGERPRINT=$(echo "$REPORT_CERT" | openssl x509 -noout -fingerprint -sha1 2>/dev/null | awk -F'=' '{print $2}')
   REPORT_CERT_SIGNATURE_ALGORITHM=$(echo "$REPORT_CERT_INFO" | grep 'Signature Algorithm' | head -n1 | awk '{print $NF}')
   REPORT_CERT_SUBJECT_KEY=$(echo "$REPORT_CERT_INFO" | grep 'Subject Key Identifier:' -A1 | tail -n1 | tr -d ' ')
   REPORT_CERT_AUTH_KEYS=$(echo "$REPORT_CERT_INFO" | grep 'Authority Key Identifier' -A3 | grep -E 'keyid:|DirName:|issuer:' | tr -d ' ')
   REPORT_CERT_KEY_USAGE=$(echo "$REPORT_CERT_INFO" | grep 'X509v3 Key Usage' -A1 | tail -n1 | sed -e 's/^ *//g' -e 's/, /\n/g' | grep -v '^$')
   REPORT_CERT_KEY_EXT_USAGE=$(echo "$REPORT_CERT_INFO" | grep 'X509v3 Extended Key Usage' -A1 | tail -n1 | sed -e 's/^ *//g' -e 's/, /\n/g' | grep -v '^$')
   REPORT_CERT_SAN=$(echo "$REPORT_CERT_INFO" | grep 'X509v3 Subject Alternative Name' -A1 | tail -n1 | sed -e 's/^ *//g' -e 's/, /\n/g' | grep -v '^$' | sort)
         
   reportLine "         Issuer: $REPORT_CERT_ISSUER" | tee -a $REPORT
   reportLine "         Subject: $REPORT_CERT_SUBJECT" | tee -a $REPORT
   reportLine "            Not Before: $REPORT_CERT_VALID_START" | tee -a $REPORT
   reportLine "            Not After : $REPORT_CERT_VALID_END" | tee -a $REPORT
   reportLine "            SHA1 Fingerprint : $REPORT_CERT_FINGERPRINT" | tee -a $REPORT
   reportLine "            Signature Algorithm: $REPORT_CERT_SIGNATURE_ALGORITHM" | tee -a $REPORT
   reportLine "            Subject Key Identifier: $REPORT_CERT_SUBJECT_KEY" | tee -a $REPORT
   
   if [ ! -z "$REPORT_CERT_AUTH_KEYS" ]; then
      reportLine "            Authority Key Identifier:" | tee -a $REPORT
      IFS=$'\n'
      for auth_key in $(echo "$REPORT_CERT_AUTH_KEYS"); do
         reportLine "               |_$auth_key" | tee -a $REPORT
         if echo "$VMDIR_CA_SUBJECT_IDS" | grep "$auth_key" > /dev/null; then ISSUER_FOUND_VMDIR=1; fi
         if echo "$VECS_CA_SUBJECT_IDS" | grep "$auth_key" > /dev/null; then ISSUER_FOUND_VECS=1; fi 
      done
      unset IFS
   fi
   
   if [[ $ISSUER_FOUND_VMDIR -eq 0 && $ISSUER_FOUND_VECS -eq 0 ]]; then
      if [[ "$REPORT_CERT_SUBJECT" == "$REPORT_CERT_ISSUER" ]]; then
         REPORT_CERT_ISSUER_FOUND="No (Self-Signed)"
      else
         REPORT_CERT_ISSUER_FOUND="No"
      fi
   elif [[ $ISSUER_FOUND_VMDIR -eq 1 && $ISSUER_FOUND_VECS -eq 0 ]]; then
      REPORT_CERT_ISSUER_FOUND="Yes, in VMware Directory"
   elif [[ $ISSUER_FOUND_VMDIR -eq 0 && $ISSUER_FOUND_VECS -eq 1 ]]; then
      REPORT_CERT_ISSUER_FOUND="Yes, in VECS"
   else
      REPORT_CERT_ISSUER_FOUND="Yes, in both"
   fi
   
   reportLine "            Key Usage:" "" | tee -a $REPORT
   if [ ! -z "$REPORT_CERT_KEY_USAGE" ]; then 
      IFS=$'\n'
      for key_usage in $(echo "$REPORT_CERT_KEY_USAGE"); do
         reportLine "               |_$key_usage" | tee -a $REPORT
      done
      unset IFS
   fi
   reportLine "            Extended Key Usage:" | tee -a $REPORT
   if [ ! -z "$REPORT_CERT_KEY_EXT_USAGE" ]; then 
      IFS=$'\n'
      for ext_key_usage in $(echo "$REPORT_CERT_KEY_EXT_USAGE"); do
         reportLine "               |_$ext_key_usage" | tee -a $REPORT
      done
      unset IFS
   fi
   reportLine "            Subject Alternative Name entries:" | tee -a $REPORT
   if [ ! -z "$REPORT_CERT_SAN" ]; then
      IFS=$'\n'
      for san in $(echo "$REPORT_CERT_SAN"); do
         reportLine "               |_$san" | tee -a $REPORT
      done
      unset IFS
   fi
   
   reportLine "            Other Information:" "" | tee -a $REPORT
   reportLine "               |_Is a Certificate Authority: $REPORT_CERT_IS_CA" "" | tee -a $REPORT
   reportLine "               |_Issuing CA in VMware Directory/VECS: $REPORT_CERT_ISSUER_FOUND" "" | tee -a $REPORT
   
   if [ ! -z $2 ]; then
      CUSTOM_INFO=$(echo "$2" | tr '|' '\n')
      IFS=$'\n'
      for custom_call in $CUSTOM_INFO; do
         FUNCTION_STRING=$(echo "$custom_call" | tr ':' ' ')
         eval $FUNCTION_STRING
      done
      unset IFS
   fi
}

#------------------------------
# Trust Anchor information for report
#------------------------------
function reportTrustAnchorDetails() {
   TRUST_ANCHOR_CERT="$1"
   SERVICE_IDS="$2"
   ENDPOINTS="$3"
   TRUST_ANCHOR_INFO=$(viewCertificateInfo "$TRUST_ANCHOR_CERT")
   TRUST_ANCHOR_SUBJECT=$(echo "$TRUST_ANCHOR_INFO" | grep 'Subject:' | awk -F'Subject: ' '{print $NF}')
   TRUST_ANCHOR_ISSUER=$(echo "$TRUST_ANCHOR_INFO" | grep 'Issuer:' | awk -F'Issuer: ' '{print $NF}')
   TRUST_ANCHOR_VALID_START=$(echo "$TRUST_ANCHOR_CERT" | openssl x509 -noout -startdate 2>/dev/null | sed 's/notBefore=//')
   TRUST_ANCHOR_VALID_END=$(echo "$TRUST_ANCHOR_CERT" | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//')
   TRUST_ANCHOR_FINGERPRINT=$(echo "$TRUST_ANCHOR_CERT" | openssl x509 -noout -fingerprint -sha1 2>/dev/null | awk -F'=' '{print $2}')
   
   
   reportLine "         Issuer: $TRUST_ANCHOR_ISSUER" | tee -a $REPORT
   reportLine "         Subject: $TRUST_ANCHOR_SUBJECT" | tee -a $REPORT
   reportLine "            Not Before: $TRUST_ANCHOR_VALID_START" | tee -a $REPORT
   reportLine "            Not After : $TRUST_ANCHOR_VALID_END" | tee -a $REPORT
   reportLine "            SHA1 Fingerprint: $TRUST_ANCHOR_FINGERPRINT" | tee -a $REPORT
   reportLine "            Service IDs:" | tee -a $REPORT
   
   for service in $SERVICE_IDS; do
      reportLine "               |_$service" | tee -a $REPORT
   done
   
   reportLine "            Endpoints:" | tee -a $REPORT
   
   for endpoint in $ENDPOINTS; do
      reportLine "               |_$endpoint" | tee -a $REPORT
   done
   
   return 0
}

#------------------------------
# Formatting for report lines
#------------------------------
function reportLine() {
   REPORT_PAD=$(printf '%0.1s' " "{1..130})
   REPORT_PAD_LENGTH=130
   
   printf '%s' "$1"
   printf '%*.*s' 0 $((REPORT_PAD_LENGTH - ${#1} - ${#2})) "$REPORT_PAD"
   printf '\n'
   
   return 0
}

#------------------------------
# Print the operation menu
#------------------------------
function operationMenu() {
   UPDATED_MACHINE_SSL=0
   UPDATED_TRUST_ANCHORS=0

   header "vCenter $VC_VERSION Certificate Management Options"
   echo " 1. Check current certificates status" | tee -a $LOG
   echo " 2. Check CA certificates in VMDir and VECS" | tee -a $LOG
   echo " 3. View Certificate Info" | tee -a $LOG
   echo " 4. Generate certificate report" | tee -a $LOG
   echo " 5. Check SSL Trust Anchors" | tee -a $LOG
   echo " 6. Update SSL Trust Anchors" | tee -a $LOG
   echo " 7. Replace the Machine SSL certificate" | tee -a $LOG
   echo " 8. Replace the Solution User certificates" | tee -a $LOG
   echo " 9. Replace the VMCA certificate and re-issue Machine SSL" | tee -a $LOG
   echo "    and Solution User certificates" | tee -a $LOG

   if [ $NODE_TYPE = "infrastructure" ]; then printf "${YELLOW}"; fi
   
   echo "10. Replace the Authentication Proxy certificate" | tee -a $LOG

   if [ $NODE_TYPE = "management" ]; then
      printf "$YELLOW"
   else
      printf "$NORMAL"
   fi

   echo "11. Replace the Auto Deploy CA certificate" | tee -a $LOG
   if [[ "$VC_VERSION" =~ ^7 ]]; then printf "$YELLOW"; fi
   echo "12. Replace the VMware Directory Service certificate" | tee -a $LOG
   if [[ "$VC_VERSION" =~ ^7 ]]; then printf "$NORMAL"; fi
   echo "13. Replace the SSO STS Signing certificate(s)" | tee -a $LOG
   printf "$NORMAL"
   echo "14. Replace all certificates with VMCA-signed" | tee -a $LOG
   echo "    certificates" | tee -a $LOG
   echo "15. Clear all certificates in the BACKUP_STORE" | tee -a $LOG
   echo "    in VECS" | tee -a $LOG
   
   if [ $NODE_TYPE = "infrastructure" ]; then printf "$YELLOW"; fi
   
   echo "16. Check vCenter Extension thumbprints" | tee -a $LOG
   printf "$NORMAL"
   echo "17. Check for SSL Interception" | tee -a $LOG
   
   if [ $NODE_TYPE = "management" ]; then
      printf "$YELLOW"
   fi
   echo "18. Check STS server certificate configuration" | tee -a $LOG
   echo "19. Check Smart Card authentication configuration" | tee -a $LOG   
   printf "$NORMAL"
   echo "20. Restart reverse proxy service" | tee -a $LOG
   echo "21. Restart all VMware services" | tee -a $LOG
   
   if cat /storage/vmware-vmon/defaultStartProfile | grep 'HACore' > /dev/null; then echo " I. vCenter High Availability information"; fi
   
   echo " E. Exit" | tee -a $LOG
   echo "" | tee -a $LOG
   
   if cat /storage/vmware-vmon/defaultStartProfile | grep 'HACore' > /dev/null; then
      echo "${YELLOW}--------------------!!! WARNING !!!--------------------"
      printf "vCenter High Availability has been configured,"
      if service-control --status vmware-vcha | grep -i stopped; then
         printf " but the\nservice is currently stopped. "
      else
         printf " and the\nservice is currently running. "
      fi
      printf "\nRestarting services will trigger a failover.\nFor more information, select option 'I' from the menu.\n\n${NORMAL}"
   fi

   read -p "Select an option [1]: " OPERATION

   if [ -z $OPERATION ]; then OPERATION=1; fi

   echo "User selected option '$OPERATION'" >> $LOG
}

#------------------------------
# Display options to view certificate info
#------------------------------
function viewCertificateMenu() {
   header "View Certificate Information"
   echo " 1. Machine SSL certificate" | tee -a $LOG
   echo " 2. Solution User certificates" | tee -a $LOG
   echo " 3. CA certificates in VMware Directory" | tee -a $LOG
   echo " 4. CA certificates in VECS" | tee -a $LOG
   
   if [ $NODE_TYPE = "infrastructure" ]; then printf "$YELLOW"; fi
   
   echo " 5. Authentication Proxy certifcate" | tee -a $LOG
   
   if [ $NODE_TYPE = "management" ]; then
      printf "$YELLOW"
   else
      printf "$NORMAL"
   fi
   
   echo " 6. VMware Directory certificate" | tee -a $LOG
   echo " 7. STS signing certificates" | tee -a $LOG
   echo " 8. VMCA certificate" | tee -a $LOG
   if configuredForCAC; then
      echo " 9. Smart Card CA certificates" | tee -a $LOG
   fi
   printf "$NORMAL"
   echo " 0. Return to main menu" | tee -a $LOG
   echo "" | tee -a $LOG
   
   read -p "Select an option [1]: " VIEW_CERT_OPERATION
   
   if [ -z $VIEW_CERT_OPERATION ]; then VIEW_CERT_OPERATION=1; fi
   
   echo "User selected option $VIEW_CERT_OPERATION" >> $LOG
   
   if [[ $VIEW_CERT_OPERATION -ne 0 ]]; then processViewCertificate; fi
}

#------------------------------
# Process options to view certificate info
#------------------------------
function processViewCertificate() {
   case $VIEW_CERT_OPERATION in 
      1)
         header "Machine SSL certificate info"
         CERT=$($VECS_CLI entry getcert --store MACHINE_SSL_CERT --alias __MACHINE_CERT)
         viewCertificateInfo "$CERT"
         ;;
      
      2)
         if [ $NODE_TYPE = "infrastructure" ]; then
            VIEW_SOLUTION_USERS="machine vsphere-webclient";
         elif [[ "$VC_VERSION" =~ ^7 ]]; then
            VIEW_SOLUTION_USERS="machine vpxd vpxd-extension vsphere-webclient wcp hvc"
         else
            VIEW_SOLUTION_USERS="machine vpxd vpxd-extension vsphere-webclient"
         fi
         for solution in $VIEW_SOLUTION_USERS; do
            header "Solution User '$solution' certificate info"
            CERT=$($VECS_CLI entry getcert --store $solution --alias $solution)
            viewCertificateInfo "$CERT"
         done
         ;;
      
      3)
         for CNID in $($DIR_CLI trustedcert list --login "$VMDIR_USER_UPN" --password "$VMDIR_USER_PASSWORD" | grep 'CN(id)' | awk '{print $NF}'); do
            header "CA $CNID certificate info"
            CERT=$($DIR_CLI trustedcert get --id $CNID --login "$VMDIR_USER_UPN" --password "$VMDIR_USER_PASSWORD" --outcert /dev/stdout)
            viewCertificateInfo "$CERT"
         done
         ;;
      
      4)
         for alias in $($VECS_CLI entry list --store TRUSTED_ROOTS --text | grep 'Alias' | awk '{print $NF}'); do
            header "CA $alias certificate info"
            CERT=$($VECS_CLI entry getcert --store TRUSTED_ROOTS --alias $alias)
            viewCertificateInfo "$CERT"
         done
         ;;
      
      5)
         if [ $NODE_TYPE = "infrastructure" ]; then
            echo "${YELLOW}The Authentication Proxy certificate is not present on the PSC. Exiting...$NORMAL"        
         else
            if [ -f /var/lib/vmware/vmcam/ssl/vmcamcert.pem ]; then
               header "Authentication Proxy certificate info"
               CERT=$(cat /var/lib/vmware/vmcam/ssl/vmcamcert.pem)
               viewCertificateInfo "$CERT"
            fi
         fi
         ;;
      
      6)
         if [ $NODE_TYPE = "management" ]; then
            echo "${YELLOW}The VMware Directory certificate is not present on the vCenter. Exiting...$NORMAL"       
         else
            header "VMware Directory certificate info"
            CERT=$(cat /usr/lib/vmware-vmdir/share/config/vmdircert.pem)
            viewCertificateInfo "$CERT"
         fi
         ;;
      
      7)
         for tenant in $($LDAP_SEARCH -LLL -h $VMDIR_FQDN -b "cn=$SSO_DOMAIN,cn=Tenants,cn=IdentityManager,cn=Services,$VMDIR_DOMAIN_DN" -D "cn=$VMDIR_USER,cn=users,$VMDIR_DOMAIN_DN" -y $STAGE_DIR/.vmdir-user-password "(objectclass=vmwSTSTenantCredential)" dn | tr -d '\n' | tr -d ' '| sed -e 's/dn:/\n&/g' -e 's/dn://g' | grep -v '^$'); do
            TENANT_CERT_COUNT=1
            TENANT_CN=$(echo ${tenant} | awk -F',' '{print $1}' | sed 's/cn=//g')
            for tenant_cert in $($LDAP_SEARCH  -LLL -h $VMDIR_FQDN -b "$tenant" -D "cn=$VMDIR_USER,cn=users,$VMDIR_DOMAIN_DN" -y $STAGE_DIR/.vmdir-user-password "(objectclass=vmwSTSTenantCredential)" userCertificate | tr -d '\n' | tr -d ' ' | sed -e 's/dn:/\n&/g' -e 's/userCertificate::/\n&/g' | grep '^userCertificate' | sed 's/userCertificate:://g'); do
               header "$TENANT_CN certificate $TENANT_CERT_COUNT info"
               TEMP_CERT="-----BEGIN CERTIFICATE-----"$'\n'
               TEMP_CERT+=$(echo $tenant_cert | fold -c64)
               TEMP_CERT+=$'\n'"-----END CERTIFICATE-----"
               viewCertificateInfo "$TEMP_CERT"
               ((++TENANT_CERT_COUNT))
            done        
         done
         ;;
      
      8)
         if [ $NODE_TYPE = "management" ]; then
            echo "${YELLOW}The VMCA certificate is not present on the vCenter. Exiting...$NORMAL"       
         else
            header "VMCA certificate info"
            CERT=$(cat /var/lib/vmware/vmca/root.cer)
            viewCertificateInfo "$CERT"
         fi
         ;;
      
      9)
         if configuredForCAC; then
            CAC_CERT_COUNT=1
            for cac_cert in $($LDAP_SEARCH -LLL -h $VMDIR_FQDN -b "cn=ClientCertAuthnTrustedCAs,cn=Default,cn=ClientCertificatePolicies,cn=$SSO_DOMAIN,cn=Tenants,cn=IdentityManager,cn=Services,$VMDIR_DOMAIN_DN" -D "cn=$VMDIR_USER,cn=users,$VMDIR_DOMAIN_DN" -y $STAGE_DIR/.vmdir-user-password "(objectclass=*)" userCertificate | tr -d '\n' | tr -d ' ' | sed -e 's/dn:/\n&/g' -e 's/userCertificate::/\n&/g' | grep '^userCertificate' | sed 's/userCertificate:://g'); do
               header "CAC CA certificate $CAC_CERT_COUNT info"
               TEMP_CERT="-----BEGIN CERTIFICATE-----"$'\n'
               TEMP_CERT+=$(echo $cac_cert | fold -c64)
               TEMP_CERT+=$'\n'"-----END CERTIFICATE-----"
               viewCertificateInfo "$TEMP_CERT"
               ((++CAC_CERT_COUNT))
            done
         fi
         ;;
      
      *)
      ;;
   esac
}

#------------------------------
# Process the operation selected by user
#------------------------------
function processOperationMenu() {
   if [[ $OPERATION =~ ^[Ee] ]]; then 
      cleanup
      exit
   fi
   
   if [[ $OPERATION =~ ^[Ii] ]]; then
      if [ $NODE_TYPE != "infrastructure" ]; then
         echo $'\n'"Whereas the official documented procedure for changing certificates in a vCenter High Availability configuration is to destroy the congifuration, make the changes, and re-configure vCenter High Availability, certificate operations can be performed as long as services are not restarted before the changes are replicated to the Passive node." | fold -c64 -s
         echo $'\n'"To verify the changes have replicated, SSH into the passive node and check the last modified time of the following files:" | fold -c64 -s
         echo $'\n'"VECS (Machine SSL, Solution Users, SMS, TRUSTED_ROOTS):"
         echo $'\t'"/storage/db/vmware-vmafd/afd.db"
         echo "VMware Directory (CA certs, STS signing cert, trust anchors):"
         echo $'\t'"/storage/db/vmware-vmdir/data.mdb"
         echo "VMware Certificate Authority (VMCA):"
         echo $'\t'"/var/lib/vmware/vmca/root.cer"
         echo "Authentication Proxy:"
         echo $'\t'"/var/lib/vmware/vmcam/ssl/rui.crt"
         echo $'\t'"/var/lib/vmware/vmcam/ssl/vmcam.pem"
         echo "Auto Deploy CA cert:"
         echo $'\t'"/etc/vmware-rbd/ssl/rbd-ca.crt"
         operationMenu
         processOperationMenu
      else
         printf "\n${YELLOW}Invalid operation${NORMAL}\n\n"
         operationMenu
         processOperationMenu
      fi
      return 0
   fi
   
   if [[ "$OPERATION" =~ ^[0-9]+$ ]]; then
      if [[ "$OPERATION" -ge 2 && "$OPERATION" -le 14 && -z $VMDIR_USER_UPN ]]; then
         getSSOCredentials

         verifySSOCredentials
      fi
      echo ""

   case $OPERATION in
      1)
         checkCerts
         operationMenu
         processOperationMenu
         ;;

      2)
         checkCACertificates
         operationMenu
         processOperationMenu
         ;;
      
      3)
         viewCertificateMenu
         operationMenu
         processOperationMenu
         ;;
      
      4)
         generateCertificateReport
         operationMenu
         processOperationMenu
         ;;
      
      5)
         checkSSLTrustAnchors
         operationMenu
         processOperationMenu
         ;;

      6)
         header "Update SSL Trust Anchors"
         getPSCLocation
         SSLTrustAnchorsSelectNode
         updateSSLTrustAnchors
         promptRestartVMwareServices
         ;;
 
      7)
         promptReplaceMachineSSL
         if replaceMachineSSLCert; then
            getPSCLocation
            SSLTrustAnchorSelf
            updateSSLTrustAnchors
            promptRestartVMwareServices
         else
            operationMenu
            processOperationMenu
         fi
         ;;

      8)
         promptReplaceSolutionUsers
         replaceSolutionUserCerts
         if [ $NODE_TYPE != "infrastructure" ]; then updateExtensionCerts; fi
         promptRestartVMwareServices
         ;;

      9)
         if [ $NODE_TYPE != "management" ]; then
            header "Replace VMCA Certificate and Re-issue Machine SSL and Solution Users"
            promptReplaceVMCA
            if replaceVMCACert; then
               replaceMachineSSLCert
               replaceSolutionUserCerts
               SSLTrustAnchorSelf
               updateSSLTrustAnchors
               if [ $NODE_TYPE != "infrastructure" ]; then updateExtensionCerts; fi
               promptRestartVMwareServices
            else
               operationMenu
               processOperationMenu
            fi
         else
            printf "\n${YELLOW}This operation must be done on the Platform Services Controller${NORMAL}\n\n"
            operationMenu
            processOperationMenu
         fi
         ;;

      10)
         if [ $NODE_TYPE != "infrastructure" ]; then
            promptReplaceAuthProxy
            replaceAuthProxyCert
            operationMenu
            processOperationMenu
         else
            printf "\n${YELLOW}This operation must be done on the vCenter Server.${NORMAL}\n\n"
            operationMenu
            processOperationMenu
         fi
         ;;
      
      11)
         if [ $NODE_TYPE != "infrastructure" ]; then
            promptReplaceAutoDeployCA
            replaceAutoDeployCACert
            operationMenu
            processOperationMenu
         else
            printf "\n${YELLOW}This operation must be done on the vCenter Server.${NORMAL}\n\n"
            operationMenu
            processOperationMenu
         fi
         ;;
      
      12)
         if [[ "$VC_VERSION" =~ ^7 ]]; then 
            printf "\n${YELLOW}This operation is not available for vCenter 7.x${NORMAL}\n\n"
            operationMenu
            processOperationMenu
         elif [ $NODE_TYPE != "management" ]; then
            promptReplaceVMDir
            replaceVMDirCert
            operationMenu
            processOperationMenu
         else
            printf "\n${YELLOW}This operation must be done on the Platform Services Controller${NORMAL}\n\n"
            operationMenu
            processOperationMenu
         fi
         ;;

      13)
         if [ $NODE_TYPE != "management" ]; then
            replaceSSOSTSCert
            promptRestartVMwareServices
         else
            printf "\n${YELLOW}This operation must be done on the Platform Services Controller${NORMAL}\n\n"
            operationMenu
            processOperationMenu
         fi
         ;;

      14)
         header "Replace All Certificates"
         VMCA_REPLACE="SELF-SIGNED"
         MACHINE_SSL_REPLACE="VMCA-SIGNED"
         SOLUTION_USER_REPLACE="VMCA-SIGNED"
         VMDIR_REPLACE="VMCA-SIGNED"
         AUTH_PROXY_REPLACE="VMCA-SIGNED"
         AUTO_DEPLOY_CA_REPLACE="SELF-SIGNED"
         getCSRInfo "1"
         case $NODE_TYPE in
            embedded|infrastructure)
               replaceVMCACert
               replaceMachineSSLCert
               replaceSolutionUserCerts
               replaceVMDirCert
               replaceSSOSTSCert
               SSLTrustAnchorSelf
               updateSSLTrustAnchors
               if [ $NODE_TYPE = "embedded" ]; then
                  replaceAuthProxyCert
                  replaceAutoDeployCACert
                  updateVCExtensionThumbprints
               fi
               promptRestartVMwareServices
               ;;

         management)
            replaceMachineSSLCert
            replaceSolutionUserCerts
            replaceAuthProxyCert
            replaceAutoDeployCACert
            SSLTrustAnchorSelf
            updateSSLTrustAnchors
            updateVCExtensionThumbprints
            promptRestartVMwareServices
            ;;
         esac
         ;;

      15)
         clearBackupStoreVECS
         operationMenu
         processOperationMenu
         ;;

      16)
         if [ $NODE_TYPE != "infrastructure" ]; then
            checkVCExtensionThumbprints
            operationMenu
            processOperationMenu
         else
            printf "\n${YELLOW}This operation must be done on the vCenter Server.${NORMAL}\n\n"
            operationMenu
            processOperationMenu
         fi
         ;;

      17)
         checkSSLInterception
         operationMenu
         processOperationMenu
         ;;

      18)
         if [ $NODE_TYPE != "management" ]; then
            checkSTSCertConfig
            operationMenu
            processOperationMenu
         else
            printf "\n${YELLOW}This operation must be done on the Platform Services Controller${NORMAL}\n\n"
            operationMenu
            processOperationMenu
         fi      
         ;;

      19)
         if [ $NODE_TYPE != "management" ]; then
            checkSmartCardConfiguration
            operationMenu
            processOperationMenu
         else
            printf "\n${YELLOW}This operation must be done on the Platform Services Controller${NORMAL}\n\n"
            operationMenu
            processOperationMenu
         fi
         ;;

      20)
         restartReverseProxy
         operationMenu
         processOperationMenu
         ;;

      21)
         restartVMwareServices
         operationMenu
         processOperationMenu
         ;;      
      
      *)
         printf "\n${YELLOW}Invalid operation${NORMAL}\n\n"
         operationMenu
         processOperationMenu
         ;;
   esac
   else
      printf "\n${YELLOW}Invalid operation${NORMAL}\n\n"
      operationMenu
      processOperationMenu
   fi
}

#------------------------------
# Prompt options for replacing VMCA certificate
#------------------------------
function promptReplaceVMCA() {
   header "Select VMCA Certificate Replacement Method"
   echo "1. Replace VMCA certificate with a self-signed certificate" | tee -a $LOG
   echo "2. Replace VMCA certificate with a CA-signed certificate" | tee -a $LOG
   read -p $'\n'"Select an option [1]: " VMCA_REPLACE_INPUT

   if [ "$VMCA_REPLACE_INPUT" == "2" ]; then VMCA_REPLACE="CA-SIGNED"; fi

   echo "User selected to replace VMCA certificate with a $VMCA_REPLACE certificate" >> $LOG 
}

#------------------------------
# Prompt options for replacing Machine SSL certificate
#------------------------------
function promptReplaceMachineSSL() {
   header "Select Machine SSL Certificate Replacement Method"
   echo "1. Replace Machine SSL certificate with a VMCA-signed certificate" | tee -a $LOG
   echo "2. Replace Machine SSL certificate with a CA-signed certificate" | tee -a $LOG
   read -p $'\n'"Select an option [1]: " MACHINE_SSL_REPLACE_INPUT

   if [ "$MACHINE_SSL_REPLACE_INPUT" == "2" ]; then MACHINE_SSL_REPLACE="CA-SIGNED"; fi

   echo "User selected to replace Machine SSL certificate with a $MACHINE_SSL_REPLACE certificate" >> $LOG
}

#------------------------------
# Prompt options for replacing Solution User certificates
#------------------------------
function promptReplaceSolutionUsers() {
   header "Select Solution User Certificate Replacement Method"
   echo "1. Replace Solution User certificates with VMCA-signed certificates" | tee -a $LOG
   echo "2. Replace Solution User certificates with CA-signed certificates" | tee -a $LOG
   read -p $'\n'"Select an option [1]: " SOLUTION_USER_REPLACE_INPUT

   if [ "$SOLUTION_USER_REPLACE_INPUT" == "2" ]; then SOLUTION_USER_REPLACE="CA-SIGNED"; fi

   echo "User selected to replace Solution User certificates with $SOLUTION_USER_REPLACE certificates" >> $LOG
}

#------------------------------
# Prompt options for replacing Authentication Proxy certificate
#------------------------------
function promptReplaceAuthProxy() {
   header "Select Authentication Proxy Certificate Replacement Method"
   echo "1. Replace Authentication Proxy certificate with VMCA-signed certificate" | tee -a $LOG
   echo "2. Replace Authentication Proxy certificate with CA-signed certificate" | tee -a $LOG
   echo ""
   read -p "Select an option [1]: " AUTH_PROXY_REPLACE_INPUT

   if [ "$AUTH_PROXY_REPLACE_INPUT" == "2" ]; then
      AUTH_PROXY_REPLACE="CA-SIGNED"
   fi

   echo "User selected to replace Authentication Proxy certifcate with a $AUTH_PROXY_REPLACE certificate" >> $LOG
}

#------------------------------
# Prompt options for replacing Auto Deploy CA certificate
#------------------------------
function promptReplaceAutoDeployCA() {
   header "Select Auto Deploy CA Certificate Replacement Method"
   echo "1. Replace Auto Deploy CA certificate with a self-signed certificate" | tee -a $LOG
   echo "2. Replace Auto Deploy CA certificate with a CA-signed certificate" | tee -a $LOG
   read -p $'\n'"Select an option [1]: " AUTO_DEPLOY_CA_REPLACE_INPUT

   if [ "$AUTO_DEPLOY_CA_REPLACE_INPUT" == "2" ]; then AUTO_DEPLOY_CA_REPLACE="CA-SIGNED"; fi
   
   echo "User selected to replace Auto Deploy CA certificate with a $AUTO_DEPLOY_CA_REPLACE certificate" >> $LOG
}

#------------------------------
# Prompt options for replacing VMDir certificate
#------------------------------
function promptReplaceVMDir() {
   header "Select VMDir Certificate Replacement Method"
   echo "1. Replace VMware Directory Service certificate with a VMCA-signed certificate" | tee -a $LOG
   echo "2. Replace VMware Directory Service certificate with a CA-signed certificate" | tee -a $LOG
   read -p $'\n'"Select an option [1]: " VMDIR_REPLACE_INPUT

   if [ "$VMDIR_REPLACE_INPUT" == "2" ]; then VMDIR_REPLACE="CA-SIGNED"; fi
   
   echo "User selected to replace VMDir certificate with a $VMDIR_REPLACE certificate" >> $LOG
}

#------------------------------
# Prompt options for the FQDN/IP of the Platform Services Controller
#------------------------------
function promptPSCLocation() {
   read -p $'\n'"Enter the FQDN/IP of the Platform Services Controller [$PSC_DEFAULT]: " PSC_LOCATION_INPUT

   if [ -z $PSC_LOCATION_INPUT ]; then
      PSC_LOCATION=$PSC_DEFAULT
   else
      PSC_LOCATION=$PSC_LOCATION_INPUT
   fi
}

#------------------------------
# Prompt to restart VMware services
#------------------------------
function promptRestartVMwareServices() {
   read -p $'\n'"Restart VMware services [no]: " RESTART_SERVICES_INPUT
   
   if [[ "$RESTART_SERVICES_INPUT" =~ ^[yY] ]]; then 
      restartVMwareServices
   else
      operationMenu
      processOperationMenu
   fi
}

#------------------------------
# Get the FQDN/IP of the Platform Services Controller
#------------------------------
function getPSCLocation() {
   if [ -z $PSC_LOCATION ]; then
      if [ $NODE_TYPE != "management" ]; then
         PSC_LOCATION=$PSC_DEFAULT
      else
         promptPSCLocation
      fi   
   fi
}

#------------------------------
# Collect information for a Certificate Signing Request
#------------------------------
function getCSRInfo() {
   header "Certificate Signing Request Information"
   read -p "Enter the country code [$CSR_COUNTRY_DEFAULT]: " CSR_COUNTRY_INPUT
   
   if [ -z $CSR_COUNTRY_INPUT ]; then 
      CSR_COUNTRY=$CSR_COUNTRY_DEFAULT
   else
      CSR_COUNTRY=$CSR_COUNTRY_INPUT
   fi

   read -p "Enter the Organization name [$CSR_ORG_DEFAULT]: " CSR_ORG_INPUT
   
   if [ -z "$CSR_ORG_INPUT" ]; then
      CSR_ORG="$CSR_ORG_DEFAULT"
   else
      CSR_ORG="$CSR_ORG_INPUT"
   fi

   read -p "Enter the Organizational Unit name [$CSR_ORG_UNIT_DEFAULT]: " CSR_ORG_UNIT_INPUT
   
   if [ -z "$CSR_ORG_UNIT_INPUT" ]; then
      CSR_ORG_UNIT="$CSR_ORG_UNIT_DEFAULT"
   else
      CSR_ORG_UNIT="$CSR_ORG_UNIT_INPUT"
   fi

   read -p "Enter the state [$CSR_STATE_DEFAULT]: " CSR_STATE_INPUT
   
   if [ -z "$CSR_STATE_INPUT" ]; then
      CSR_STATE="$CSR_STATE_DEFAULT"
   else
      CSR_STATE="$CSR_STATE_INPUT"
   fi

   read -p "Enter the locality (city) name [$CSR_LOCALITY_DEFAULT]: " CSR_LOCALITY_INPUT
   
   if [ -z "$CSR_LOCALITY_INPUT" ]; then
      CSR_LOCALITY="$CSR_LOCALITY_DEFAULT"
   else
      CSR_LOCALITY="$CSR_LOCALITY_INPUT"
   fi

   read -p "Enter the IP address (optional): " CSR_IP_INPUT
   
   if [ ! -z $CSR_IP_INPUT ]; then CSR_IP=$CSR_IP_INPUT; fi

   read -p "Enter an email address (optional): " CSR_EMAIL_INPUT
   
   if [ ! -z $CSR_EMAIL_INPUT ]; then CSR_EMAIL=$CSR_EMAIL_INPUT; fi
   
   if [ ! -z $1 ]; then
      read -p "Enter any additional hostnames for SAN entries (comma separated value): " CSR_SAN_INPUT
   
      if [ ! -z $CSR_SAN_INPUT ]; then CSR_ADDITIONAL_DNS=$CSR_SAN_INPUT; fi      
   fi
}

#------------------------------
# Generate a configuration file to be used with the openssl commands
#------------------------------
function generateOpensslConfig() {
   echo "The following items will be added as Subject Alternative Name entries on the '$3' Certificate Signing Request:"
   echo $'\n'"$CYAN$HOSTNAME"
   echo "$HOSTNAME_SHORT"
   if [ "$HOSTNAME_LC" != "$PNID_LC" ]; then
      echo "$PNID"
   fi
   
   if [ ! -z $CSR_IP ]; then echo "$CSR_IP"; fi
   
   if [ ! -z $CSR_EMAIL ]; then echo "$CSR_EMAIL"; fi
   
   echo "$NORMAL"
   read -p "If you want any additional items added as Subject Alternative Name entries, enter them as a comma-separated list (optional): " ADDITIONAL_SAN_ITEMS

   echo "[ req ]" > $2
   echo "prompt = no" >> $2
   echo "default_bits = 2048" >> $2
   echo "distinguished_name = req_distinguished_name" >> $2
   echo "req_extensions = v3_req" >> $2
   echo "" >> $2
   echo "[ req_distinguished_name ]" >> $2
   echo "C = $CSR_COUNTRY" >> $2
   echo "ST = $CSR_STATE" >> $2
   echo "L = $CSR_LOCALITY" >> $2
   echo "O = $CSR_ORG" >> $2
   echo "OU = $CSR_ORG_UNIT" >> $2
   echo "CN = $1" >> $2
   echo "" >> $2
   echo "[ v3_req ]" >> $2
   printf "subjectAltName = DNS:$HOSTNAME, DNS:$HOSTNAME_SHORT" >> $2
   
   if [ "$HOSTNAME_LC" != "$PNID_LC" ]; then
      printf ", DNS:$PNID" >> $2
   fi
   
   for item in $(echo $ADDITIONAL_SAN_ITEMS | sed -e 's/,/\n/g'); do
      if [[ $item =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
         printf ", IP:$item" >> $2
      else
         printf ", DNS:$item" >> $2
      fi      
   done

   if [ ! -z $CSR_IP ]; then printf ", IP:$CSR_IP" >> $2; fi

   if [ ! -z $CSR_EMAIL ]; then printf ", email:$CSR_EMAIL" >> $2; fi
}

#------------------------------
# Generate a certificate Signing Request
#------------------------------
function generateCSR() {
   openssl req -new -newkey rsa:2048 -nodes -out $1 -keyout $2 -config $3 >> $LOG 2>&1
   return 0
}

#------------------------------
# Generate a configuration file for the certool utility
#------------------------------
function generateCertoolConfig() {
   echo "Country = $CSR_COUNTRY" > $STAGE_DIR/$2
   echo "Name = $1" >> $STAGE_DIR/$2
   echo "Organization = $CSR_ORG" >> $STAGE_DIR/$2
   echo "OrgUnit = $CSR_ORG_UNIT" >> $STAGE_DIR/$2
   echo "State = $CSR_STATE" >> $STAGE_DIR/$2
   echo "Locality = $CSR_LOCALITY" >> $STAGE_DIR/$2
   
   if [ $1 == $IP ]; then
      echo "IPAddress = $1" >> $STAGE_DIR/$2
   elif [ ! -z $CSR_IP ]; then 
      echo "IPAddress = $CSR_IP" >> $STAGE_DIR/$2
   fi
   
   if [ ! -z $CSR_EMAIL ]; then echo "Email = $CSR_EMAIL" >> $STAGE_DIR/$2; fi
   
   printf "Hostname = $HOSTNAME" >> $STAGE_DIR/$2
   
   if [ "$HOSTNAME_LC" != "$PNID_LC" ] && [ "$IP" != "$PNID" ]; then
      printf ",$PNID" >> $STAGE_DIR/$2
   fi
   
   if [ ! -z $CSR_ADDITIONAL_DNS ]; then
      printf ",$CSR_ADDITIONAL_DNS" >> $STAGE_DIR/$2
   fi
}

#------------------------------
# Generate configuration for VMDir certificate to be generated by the certool utility
#------------------------------
function generateVmdirCertoolConfig() {
   task "Generate certool configuration"
   echo "Country = $CSR_COUNTRY" > $STAGE_DIR/vmdir.cfg
   echo "Name = $HOSTNAME" >> $STAGE_DIR/vmdir.cfg
   echo "Hostname = $HOSTNAME" >> $STAGE_DIR/vmdir.cfg
   taskMessage "OK" "GREEN"
}

#------------------------------
# Generate configuration for Authentication Proxy certificate to be generated by the certool utility
#------------------------------
function generateAuthProxyCertoolConfig() {
   task "Generate certool configuration"
   echo "Country = $CSR_COUNTRY" > $STAGE_DIR/auth-proxy.cfg
   echo "Organization = $CSR_ORG" >> $STAGE_DIR/auth-proxy.cfg
   echo "OrgUnit = $CSR_ORG_UNIT" >> $STAGE_DIR/auth-proxy.cfg
   echo "Name = $HOSTNAME" >> $STAGE_DIR/auth-proxy.cfg
   echo "Hostname = $HOSTNAME" >> $STAGE_DIR/auth-proxy.cfg
   taskMessage "OK" "GREEN"
}

#------------------------------
# Generate configuration for STS signing certificate to be generated by the certool utility
#------------------------------
function generateSSOSTSCertoolConfig() {
   task "Generate certool configuration"
   echo "Name = ssoserverSign" > $STAGE_DIR/sso-sts.cfg
   echo "Hostname = $HOSTNAME" >> $STAGE_DIR/sso-sts.cfg
   taskMessage "OK" "GREEN"
}

#------------------------------
# Get the VMCA certificate
#------------------------------
function getVMCACert() {
   if [ $NODE_TYPE != "management" ]; then
      VMCA_CERT="/var/lib/vmware/vmca/root.cer"
   else
      VMCA_CERT_SERIAL=$($CERTOOL --getrootca --server $PSC_LOCATION | grep -A 1 'Serial Number:' | tail -n1 | tr -d ' ')
      TRUSTED_ROOT_COUNTER=1
      
      for id in $($DIR_CLI trustedcert list --login $VMDIR_USER --password "$(cat $STAGE_DIR/.vmdir-user-password)" | grep '^CN' | awk '{print $2}'); do
         $DIR_CLI trustedcert get --id $id --login $VMDIR_USER --password "$(cat $STAGE_DIR/.vmdir-user-password)" --outcert $STAGE_DIR/trusted-root$TRUSTED_ROOT_COUNTER.crt
         TRUSTED_ROOT_SERIAL=$(openssl x509 -text -noout -in $STAGE_DIR/trusted-root$TRUSTED_ROOT_COUNTER.crt 2>/dev/null | grep -A 1 'Serial Number:' | tail -n1 | tr -d ' ')
         
     if [ "$TRUSTED_ROOT_SERIAL" == "$VMCA_CERT_SERIAL" ]; then VMCA_CERT="$STAGE_DIR/trusted-root$TRUSTED_ROOT_COUNTER.crt"; fi
        
     ((++TRUSTED_ROOT_COUNTER))   
      done
   fi
}

#------------------------------
# Replace the VMCA certificate
#------------------------------
function replaceVMCACert() {
   header "Replace VMCA Certificate"
   if [ $VMCA_REPLACE == "SELF-SIGNED" ]; then
      VMCA_CERT=$STAGE_DIR/vmca.crt
      VMCA_KEY=$STAGE_DIR/vmca.key
      
      if [ -z $CSR_COUNTRY ]; then getCSRInfo; fi
      
      read -p "Enter the CommonName for the VMCA certificate [$VMCA_CN_DEFAULT]: " VMCA_CN_INPUT
         
      if [ -z $VMCA_CN_IPUT ]; then
         VMCA_CN="$VMCA_CN_DEFAULT"
      else
         VMCA_CN=$VMCA_CN_INPUT
      fi
     
      task "Generate certool configuration"
      generateCertoolConfig "$VMCA_CN" "vmca.cfg"
      taskMessage "OK" "GREEN"
      
      task "Generate VMCA certificate"
      $CERTOOL --genselfcacert --outcert=$VMCA_CERT --outprivkey=$VMCA_KEY --config=$STAGE_DIR/vmca.cfg >> $LOG 2>&1 || errorMessage "Unable to generate new VMCA certificate"
      taskMessage "OK" "GREEN"

   else
      echo $'\n'"1. Generate Certificate Signing Request and Private Key" | tee -a $LOG
      echo "2. Import CA-signed certificate and key"
      read -p $'\n'"Choose option [1]: " VMCA_CA_SIGNED_OPTION

      if [ "$VMCA_CA_SIGNED_OPTION" == "2" ]; then      
         read -p "Provide path to the CA-signed ${CYAN}VMCA${NORMAL} certificate: " VMCA_CERT_INPUT
         while [ ! -f "$VMCA_CERT_INPUT" ]; do read -p "${YELLOW}File not found, please provide path to the CA-signed ${RED}VMCA${YELLOW} certificate:${NORMAL} " VMCA_CERT_INPUT; done
         VMCA_CERT=$(getCorrectCertFormat "$VMCA_CERT_INPUT")
         
         read -p "Provide path to the ${CYAN}VMCA${NORMAL} private key: " VMCA_KEY_INPUT
         while [ ! -f "$VMCA_KEY_INPUT" ]; do read -p "${YELLOW}File not found, please provide path to the CA-signed ${RED}VMCA${YELLOW} private key:${NORMAL} " VMCA_KEY_INPUT; done
         VMCA_KEY=$(getCorrectKeyFormat "$VMCA_KEY_INPUT")
         
         getCAChain "$VMCA_CERT"
                  
         task "Verifying certificate and key: "
         verifyCertAndKey $VMCA_CERT $VMCA_KEY $TRUSTED_ROOT_CHAIN
         taskMessage "OK" "GREEN"
         
         task "Verifying CA certificate: "
         isCertCA "$(cat $VMCA_CERT)" || errorMessage "The provided certificate $VMCA_CERT is not a CA certificate."
         taskMessage "OK" "GREEN"
      else
         VMCA_CSR=$REQUEST_DIR/vmca-$TIMESTAMP.csr
         VMCA_KEY=$REQUEST_DIR/vmca-$TIMESTAMP.key
         VMCA_CFG=$REQUEST_DIR/vmca.cfg
         
         if [ -z $CSR_COUNTRY ]; then getCSRInfo; fi
         
         read -p $'\n'"Enter a value for the ${CYAN}CommonName${NORMAL} of the certificate [CA]: " VMCA_COMMON_NAME

         if [ -z $VMCA_COMMON_NAME ]; then VMCA_COMMON_NAME="CA"; fi

         generateOpensslConfig $VMCA_COMMON_NAME $VMCA_CFG "vmca"
         generateCSR $VMCA_CSR $VMCA_KEY $VMCA_CFG
         
         printf "\nCertificate Signing Request generated at ${CYAN}${VMCA_CSR}${NORMAL}"
         printf "\nPrivate Key generated at ${CYAN}${VMCA_KEY}${NORMAL}\n\n"
         
         exit
      fi
   fi
   
   backupFilesystemCertKey "/var/lib/vmware/vmca/root.cer" "/var/lib/vmware/vmca/privatekey.pem" "VMCA"
   
   task "Reconfigure VMCA"
   $CERTOOL --rootca --cert=$VMCA_CERT --privkey=$VMCA_KEY >> $LOG 2>&1 || errorMessage "Unable to reconfigure the VMCA with the new certificate"
   taskMessage "OK" "GREEN"
    
   if [ $VMCA_REPLACE == "CA-SIGNED" ]; then
      task "Publish CA certificates to VMDir"
      $DIR_CLI trustedcert publish --chain --cert $TRUSTED_ROOT_CHAIN --login $VMDIR_USER_UPN --password "$(cat $STAGE_DIR/.vmdir-user-password)" >> $LOG 2>&1 || errorMessage "Unable to publish trusted root chain to VMDir"
      taskMessage "OK" "GREEN"
   fi
   
   if [ -f /etc/vmware-sso/keys/ssoserverRoot.crt ]; then
      task "Update VMCA certificate on filesystem"
      mv /etc/vmware-sso/keys/ssoserverRoot.crt /etc/vmware-sso/keys/ssoserverRoot.crt.old >> $LOG 2>&1 || errorMessage "Unable to backup old SSO server root certificate"
      cp $VMCA_CERT /etc/vmware-sso/keys/ssoserverRoot.crt >> $LOG 2>&1 || errorMessage "Unable to update SSO server root certificate"
      taskMessage "OK" "GREEN"
   fi
   
   return 0
}

#------------------------------
# Replace the Machine SSL certificate
#------------------------------
function replaceMachineSSLCert() {
   if [ $MACHINE_SSL_REPLACE == "VMCA-SIGNED" ]; then
      MACHINE_SSL_CERT=$STAGE_DIR/machine-ssl.crt
      MACHINE_SSL_PUBKEY=$STAGE_DIR/machine-ssl.pub
      MACHINE_SSL_KEY=$STAGE_DIR/machine-ssl.key

      getPSCLocation

      if [ -z $CSR_COUNTRY ]; then getCSRInfo "1"; fi

      header "Replace Machine SSL Certificate"
   
      task "Generate certool configuration"
      generateCertoolConfig $PNID "machine-ssl.cfg"
      taskMessage "OK" "GREEN"

      task "Regenerate Machine SSL certificate"
      regenerateSelfSignedCertificate "machine-ssl"
      taskMessage "OK" "GREEN"
   else
      echo $'\n'"1. Generate Certificate Signing Request and Private Key" | tee -a $LOG
      echo "2. Import CA-signed certificate and key" | tee -a $LOG
      read -p $'\n'"Choose option [1]: " MACHINE_SSL_CA_SIGNED_OPTION

      if [ "$MACHINE_SSL_CA_SIGNED_OPTION" == "2" ]; then
         echo "User has chosen to import a CA-signed Machine SSL certificate and key" >> $LOG     
         read -p $'\n'"Provide path to the CA-signed ${CYAN}Machine SSL${NORMAL} certificate: " MACHINE_SSL_CERT_INPUT
         while [ ! -f "$MACHINE_SSL_CERT_INPUT" ]; do read -p "${YELLOW}File not found, please provide path to the ${RED}Machine SSL${YELLOW} certificate:${NORMAL} " MACHINE_SSL_CERT_INPUT; done
         
         MACHINE_SSL_CERT=$(getCorrectCertFormat "$MACHINE_SSL_CERT_INPUT")
         
         read -p "Provide path to the ${CYAN}Machine SSL${NORMAL} private key: " MACHINE_SSL_KEY_INPUT
         while [ ! -f "$MACHINE_SSL_KEY_INPUT" ]; do read -p "${YELLOW}File not found, please provide path to the ${RED}Machine SSL${YELLOW} private key:${NORMAL} " MACHINE_SSL_KEY_INPUT; done
         
         MACHINE_SSL_KEY=$(getCorrectKeyFormat "$MACHINE_SSL_KEY_INPUT")
         
         getCAChain "$MACHINE_SSL_CERT"

         echo ""
         task "Verifying certificate and key"        
        
         echo "Using Machine SSL cert: $MACHINE_SSL_CERT" >> $LOG
         echo "Using Private Key: $MACHINE_SSL_KEY" >> $LOG
         echo "Using trusted root chain: $TRUSTED_ROOT_CHAIN" >> $LOG
        
         verifyCertAndKey $MACHINE_SSL_CERT $MACHINE_SSL_KEY 
         taskMessage "OK" "GREEN"
        
         task "Verifying root chain"
         verifyRootChain $MACHINE_SSL_CERT $TRUSTED_ROOT_CHAIN || errorMessage "Certificate Authority chain is not complete."
         taskMessage "OK" "GREEN"
                
         task "Verify PNID included in SAN"
         cat "$MACHINE_SSL_CERT" | openssl x509 -noout -text 2>/dev/null | grep -A1 'Subject Alternative Name' | grep -i "$PNID" > /dev/null || errorMessage "The Primary Network Identifier (PNID) is not included in the Subject Alternative Name field."
         taskMessage "OK" "GREEN"       
        
         header "Replace Machine SSL Certificate"

         task "Backup current certificate and key"
         $VECS_CLI entry getcert --store MACHINE_SSL_CERT --alias __MACHINE_CERT > $BACKUP_DIR/previous-machine-ssl.crt
         $VECS_CLI entry getkey --store MACHINE_SSL_CERT --alias __MACHINE_CERT > $BACKUP_DIR/previous-machine-ssl.key
         taskMessage "OK" "GREEN"
         
         task "Pubish CA signing certificates"
         $DIR_CLI trustedcert publish --chain --cert $TRUSTED_ROOT_CHAIN --login $VMDIR_USER_UPN --password "$(cat $STAGE_DIR/.vmdir-user-password)" >> $LOG 2>&1 || errorMessage "Unable to publish trusted root chain to VMDir"
         taskMessage "OK" "GREEN"
      else
         echo "User has chosen to generate the Machine SSL private key and CSR" >> $LOG
         MACHINE_SSL_CSR=$REQUEST_DIR/machine-ssl-$TIMESTAMP.csr
         MACHINE_SSL_KEY=$REQUEST_DIR/machine-ssl-$TIMESTAMP.key
         MACHINE_SSL_CFG=$REQUEST_DIR/machine-ssl.cfg
         
         if [ -z $CSR_COUNTRY ]; then getCSRInfo; fi

         read -p "Enter a value for the ${CYAN}CommonName${NORMAL} of the certificate [$HOSTNAME]: " MACHINE_SSL_COMMON_NAME

         if [ -z $MACHINE_SSL_COMMON_NAME ]; then MACHINE_SSL_COMMON_NAME=$HOSTNAME; fi

         generateOpensslConfig $MACHINE_SSL_COMMON_NAME $MACHINE_SSL_CFG "machine-ssl"
         generateCSR $MACHINE_SSL_CSR $MACHINE_SSL_KEY $MACHINE_SSL_CFG
         
     printf "\nCertificate Signing Request generated at ${CYAN}${MACHINE_SSL_CSR}${NORMAL}"
         printf "\nPrivate Key generated at ${CYAN}${MACHINE_SSL_KEY}${NORMAL}\n\n"

         exit
      fi
   fi
   
   backupVECSCertKey "machine-ssl"
   
   updateVECS "machine-ssl"

   if checkLookupServiceVECSStore; then
      updateVECS "legacy-lookup-service" "machine-ssl"
   fi
   
   task "Update certificate on filesystem"
   mv /etc/applmgmt/appliance/server.pem /etc/applmgmt/appliance/server.pem.old >> $LOG 2>&1 || errorMessage "Unable to backup applmgmt service PEM file"
   cat $MACHINE_SSL_CERT $MACHINE_SSL_KEY > /etc/applmgmt/appliance/server.pem || errorMessage "Unable to create new applmgmt service PEM file"

   mv /etc/vmware/vmware-vmafd/machine-ssl.crt /etc/vmware/vmware-vmafd/machine-ssl.crt.old >> $LOG 2>&1 || errorMessage "Unable to backup Authentication Framework certificate"
   mv /etc/vmware/vmware-vmafd/machine-ssl.key /etc/vmware/vmware-vmafd/machine-ssl.key.old >> $LOG 2>&1 || errorMessage "Unable to backup Authentication Framework private key"
   cp $MACHINE_SSL_CERT /etc/vmware/vmware-vmafd/machine-ssl.crt >> $LOG 2>&1 || errorMessage "Unable to update Authentication Framework certificate"
   cp $MACHINE_SSL_KEY /etc/vmware/vmware-vmafd/machine-ssl.key >> $LOG 2>&1 || errorMessage "Unable to update Authentication Framework private key"
   taskMessage "OK" "GREEN"
   
   UPDATED_MACHINE_SSL=1

   return 0
}

#------------------------------
# Replace Solution User certificates
#------------------------------
function replaceSolutionUserCerts() {
   if [ $SOLUTION_USER_REPLACE == "VMCA-SIGNED" ]; then
      MACHINE_CERT=$STAGE_DIR/machine.crt
      MACHINE_KEY=$STAGE_DIR/machine.key
      VPXD_CERT=$STAGE_DIR/vpxd.crt
      VPXD_KEY=$STAGE_DIR/vpxd.key
      VPXD_EXT_CERT=$STAGE_DIR/vpxd-extension.crt
      VPXD_EXT_KEY=$STAGE_DIR/vpxd-extension.key
      WEBCLIENT_CERT=$STAGE_DIR/vsphere-webclient.crt
      WEBCLIENT_KEY=$STAGE_DIR/vsphere-webclient.key
      WCP_CERT=$STAGE_DIR/wcp.crt
      WCP_KEY=$STAGE_DIR/wcp.key
      HVC_CERT=$STAGE_DIR/hvc.crt
      HVC_KEY=$STAGE_DIR/hvc.key

      getPSCLocation

      if [ -z $CSR_COUNTRY ]; then getCSRInfo; fi

      header "Replace Solution User Certificates"
      
      echo "Generate certool configurations:"
      
      task "machine"
      generateCertoolConfig "machine-$MACHINE_ID" "machine.cfg"
      taskMessage "OK" "GREEN"
      task "vsphere-webclient"
      generateCertoolConfig "vsphere-webclient-$MACHINE_ID" "vsphere-webclient.cfg"
      taskMessage "OK" "GREEN"
      
      if [ $NODE_TYPE != "infrastructure" ]; then
         task "vpxd"
         generateCertoolConfig "vpxd-$MACHINE_ID" "vpxd.cfg"
         taskMessage "OK" "GREEN"
         
         task "vpxd-extension"
         generateCertoolConfig "vpxd-extension-$MACHINE_ID" "vpxd-extension.cfg"
         taskMessage "OK" "GREEN"
         
         if [[ "$VC_VERSION" =~ ^7 ]]; then
            task "wcp"
            generateCertoolConfig "wcp-$MACHINE_ID" "wcp.cfg"
            taskMessage "OK" "GREEN"
            
            task "hvc"
            generateCertoolConfig "hvc-$MACHINE_ID" "hvc.cfg"
            taskMessage "OK" "GREEN"
         fi
      fi
      
      echo $'\n'"Generate new certificates:"
      
      task "machine"
      regenerateSelfSignedCertificate "machine"
      taskMessage "OK" "GREEN"
      
      task "vsphere-webclient"
      regenerateSelfSignedCertificate "vsphere-webclient"
      taskMessage "OK" "GREEN"
      
      if [ $NODE_TYPE != "infrastructure" ]; then
         task "vpxd"
         regenerateSelfSignedCertificate "vpxd"
         taskMessage "OK" "GREEN"
         
         task "vpxd-extension"
         regenerateSelfSignedCertificate "vpxd-extension"
         taskMessage "OK" "GREEN"
         
         if [[ "$VC_VERSION" =~ ^7 ]]; then
            task "wcp"
            regenerateSelfSignedCertificate "wcp"
            taskMessage "OK" "GREEN"
            
            task "hvc"
           regenerateSelfSignedCertificate "hvc"
           taskMessage "OK" "GREEN"
         fi
      fi           
   else
      echo $'\n'"1. Generate Certificate Signing Requests and Private Keys" | tee -a $LOG
      echo "2. Import CA-signed certificates and keys" | tee -a $LOG
      read -p $'\n'"Choose option [1]: " SOLUTION_USERS_CA_SIGNED_OPTION

      if [ "$SOLUTION_USERS_CA_SIGNED_OPTION" == "2" ]; then
      echo "User has chosen to import a CA-signed Solution User certificates and keys" >> $LOG
         read -p $'\n'"Provide path to the CA-signed ${CYAN}machine${NORMAL} certificate: " MACHINE_CERT_INPUT
         while [ ! -f "$MACHINE_CERT_INPUT" ]; do read -p "${YELLOW}File not found, please provide path to the ${RED}machine${YELLOW} certificate:${NORMAL} " MACHINE_CERT_INPUT; done
         
         MACHINE_CERT=$(getCorrectCertFormat "$MACHINE_CERT_INPUT")
         
         read -p "Provide path to the ${CYAN}machine${NORMAL} private key: " MACHINE_KEY_INPUT
         while [ ! -f "${MACHINE_KEY_INPUT}" ]; do read -p "${YELLOW}File not found, please provide path to the ${RED}machine${YELLOW} private key:${NORMAL} " MACHINE_KEY_INPUT; done
         
         MACHINE_KEY=$(getCorrectKeyFormat "$MACHINE_KEY_INPUT")

         if [ $NODE_TYPE != "infrastructure" ]; then
            read -p $'\n'"Provide path to the CA-signed ${CYAN}vpxd${NORMAL} certificate: " VPXD_CERT_INPUT
            while [ ! -f "$VPXD_CERT_INPUT" ]; do read -p "${YELLOW}File not found, please provide path to the ${RED}vpxd${YELLOW} certificate:${NORMAL} " VPXD_CERT_INPUT; done
            VPXD_CERT=$(getCorrectCertFormat "$VPXD_CERT_INPUT")
            read -p "provide path to the ${CYAN}vpxd${NORMAL} private key: " VPXD_KEY_INPUT
            while [ ! -f "$VPXD_KEY_INPUT" ]; do read -p "${YELLOW}File not found, please provide path to the ${RED}vpxd${YELLOW} private key:${NORMAL} " VPXD_KEY_INPUT; done
            VPXD_KEY=$(getCorrectKeyFormat "$VPXD_KEY_INPUT")
            read -p $'\n'"Provide path to the CA-signed ${CYAN}vpxd-extension${NORMAL} certificate: " VPXD_EXT_CERT_INPUT
            while [ ! -f "$VPXD_EXT_CERT_INPUT" ]; do read -p "${YELLOW}File not found, please provide path to the ${RED}vpxd-extension${YELLOW} certificate:${NORMAL} " VPXD_EXT_CERT_INPUT; done
            VPXD_EXT_CERT=$(getCorrectCertFormat "$VPXD_EXT_CERT_INPUT")
            read -p "Provide path to the ${CYAN}vpxd-extension${NORMAL} private key: " VPXD_EXT_KEY_INPUT
            while [ ! -f "$VPXD_EXT_KEY_INPUT" ]; do read -p "${YELLOW}File not found, please provide path to the ${RED}vpxd-extension${YELLOW} certificate:${NORMAL} " VPXD_EXT_KEY_INPUT; done
            VPXD_EXT_KEY=$(getCorrectKeyFormat "$VPXD_EXT_KEY_INPUT")
         fi

         read -p $'\n'"Provide path to the CA-signed ${CYAN}vsphere-webclient${NORMAL} certificate: " WEBCLIENT_CERT_INPUT
         while [ ! -f "$WEBCLIENT_CERT_INPUT" ]; do read -p "${YELLOW}File not found, please provide path to the ${RED}vsphere-webclient${YELLOW} certificate:${NORMAL} " WEBCLIENT_CERT_INPUT; done
         WEBCLIENT_CERT=$(getCorrectCertFormat "$WEBCLIENT_CERT_INPUT")
         read -p "Provide path to the ${CYAN}vsphere-webclient${NORMAL} private key: " WEBCLIENT_KEY_INPUT
         while [ ! -f "$WEBCLIENT_KEY_INPUT" ]; do read -p "${YELLOW}File not found, please provide path to the ${RED}vsphere-webclient${YELLOW} private key:${NORMAL} " WEBCLIENT_KEY_INPUT; done
         WEBCLIENT_KEY=$(getCorrectKeyFormat "$WEBCLIENT_KEY_INPUT")
         
         if [[ "$VC_VERSION" =~ ^7 ]]; then
            read -p $'\n'"Provide path to the CA-signed ${CYAN}wcp${NORMAL} certificate: " WCP_CERT_INPUT
            while [ ! -f "$WCP_CERT_INPUT" ]; do read -p "${YELLOW}File not found, please provide path to the ${RED}wcp${YELLOW} certificate:${NORMAL} " WCP_CERT_INPUT; done
            WCP_CERT=$(getCorrectCertFormat "$WCP_CERT_INPUT")
            read -p "Provide path to the ${CYAN}wcp${NORMAL} private key: " WCP_KEY_INPUT
            while [ ! -f "$WCP_KEY_INPUT" ]; do read -p "${YELLOW}File not found, please provide path to the ${RED}wcp${YELLOW} private key:${NORMAL} " WCP_KEY_INPUT; done
            WCP_KEY=$(getCorrectKeyFormat "$WCP_KEY_INPUT")
            
            read -p $'\n'"Provide path to the CA-signed ${CYAN}hvc${NORMAL} certificate: " HVC_CERT_INPUT
            while [ ! -f "$HVC_CERT_INPUT" ]; do read -p "${YELLOW}File not found, please provide path to the ${RED}hvc${YELLOW} certificate:${NORMAL} " HVC_CERT_INPUT; done
            HVC_CERT=$(getCorrectCertFormat "$HVC_CERT_INPUT")
            read -p "Provide path to the ${CYAN}hvc${NORMAL} private key: " HVC_KEY_INPUT
            while [ ! -f "$HVC_KEY_INPUT" ]; do read -p "${YELLOW}File not found, please provide path to the ${RED}hvc${YELLOW} private key:${NORMAL} " HVC_KEY_INPUT; done
            HVC_KEY=$(getCorrectKeyFormat "$HVC_KEY_INPUT")
         fi
         
         getCAChain "$MACHINE_CERT"      
         
         task "Verifying certificates and keys: "
         verifyCertAndKey $MACHINE_CERT $MACHINE_KEY 
         if [ $NODE_TYPE != "infrastructure" ]; then
            verifyCertAndKey $VPXD_CERT $VPXD_KEY 
            verifyCertAndKey $VPXD_EXT_CERT $VPXD_EXT_KEY 
         fi

         verifyCertAndKey $WEBCLIENT_CERT $WEBCLIENT_KEY 
         
         if [[ "${VC_VERSION}" =~ ^7 ]]; then 
            verifyCertAndKey $WCP_CERT $WCP_KEY 
            verifyCertAndKey $HVC_CERT $HVC_KEY 
         fi
         
         taskMessage "OK" "GREEN"
         
         task "Verifying root chain"
         verifyRootChain $MACHINE_CERT $TRUSTED_ROOT_CHAIN || errorMessage "Certificate Authority chain is not complete."
         taskMessage "OK" "GREEN"
      else
         MACHINE_CSR=$REQUEST_DIR/machine-$TIMESTAMP.csr
         MACHINE_KEY=$REQUEST_DIR/machine-$TIMESTAMP.key
         MACHINE_CFG=$REQUEST_DIR/machine.cfg
         VPXD_CSR=$REQUEST_DIR/vpxd-$TIMESTAMP.csr
         VPXD_KEY=$REQUEST_DIR/vpxd-$TIMESTAMP.key
         VPXD_CFG=$REQUEST_DIR/vpxd.cfg
         VPXD_EXT_CSR=$REQUEST_DIR/vpxd-extension-$TIMESTAMP.csr
         VPXD_EXT_KEY=$REQUEST_DIR/vpxd-extension-$TIMESTAMP.key
         VPXD_EXT_CFG=$REQUEST_DIR/vpxd-extension.cfg
         WEBCLIENT_CSR=$REQUEST_DIR/vsphere-webclient-$TIMESTAMP.csr
         WEBCLIENT_KEY=$REQUEST_DIR/vsphere-webclient-$TIMESTAMP.key
         WEBCLIENT_CFG=$REQUEST_DIR/vsphere-webclient.cfg
         
         if [[ "${VC_VERSION}" =~ ^7 ]]; then
            WCP_CSR=$REQUEST_DIR/wcp-$TIMESTAMP.csr
            WCP_KEY=$REQUEST_DIR/wcp-$TIMESTAMP.key
            WCP_CFG=$REQUEST_DIR/wcp.cfg
            
            HVC_CSR=$REQUEST_DIR/hvc-$TIMESTAMP.csr
            HVC_KEY=$REQUEST_DIR/hvc-$TIMESTAMP.key
            HVC_CFG=$REQUEST_DIR/hvc.cfg
         fi

         if [ -z $CSR_COUNTRY ]; then getCSRInfo; fi

         generateOpensslConfig "machine-${MACHINE_ID}" $MACHINE_CFG "machine"
         generateCSR $MACHINE_CSR $MACHINE_KEY $MACHINE_CFG

         if [ $NODE_TYPE != "infrastructure" ]; then
            generateOpensslConfig "vpxd-${MACHINE_ID}" $VPXD_CFG "vpxd"
            generateCSR $VPXD_CSR $VPXD_KEY $VPXD_CFG
            generateOpensslConfig "vpxd-extension-${MACHINE_ID}" $VPXD_EXT_CFG "vpxd-extension"
            generateCSR $VPXD_EXT_CSR $VPXD_EXT_KEY $VPXD_EXT_CFG
         fi

         generateOpensslConfig "vsphere-webclient-${MACHINE_ID}" $WEBCLIENT_CFG "vsphere-webclient"
         generateCSR $WEBCLIENT_CSR $WEBCLIENT_KEY $WEBCLIENT_CFG
         
         if [[ "${VC_VERSION}" =~ ^7 ]]; then
            generateOpensslConfig "wcp-${MACHINE_ID}" $WCP_CFG "wcp"
            generateCSR $WCP_CSR $WCP_KEY $WCP_CFG
            
            generateOpensslConfig "hvc-${MACHINE_ID}" $HVC_CFG "hvc"
            generateCSR $HVC_CSR $HVC_KEY $HVC_CFG
         fi
         
         printf "\nCertificate Signing Requests generated at:"
         printf "\n${CYAN}${MACHINE_CSR}"

         if [ $NODE_TYPE != "infrastructure" ]; then
            printf "\n$VPXD_CSR\n$VPXD_EXT_CSR"
         fi
         
         if [[ "$VC_VERSION" =~ ^7 ]]; then 
            printf "\n$WCP_CSR\n$HVC_CSR"   
         fi
         
         printf "\n${WEBCLIENT_CSR}${NORMAL}"                
         
         printf "\n\nPrivate Keys generated at:"
         printf "\n${CYAN}${MACHINE_KEY}"

         if [ $NODE_TYPE != "infrastructure" ]; then
            printf "\n$VPXD_KEY\n$VPXD_EXT_KEY"
         fi
         
         if [[ "$VC_VERSION" =~ ^7 ]]; then 
            printf "\n$WCP_KEY\n$HVC_KEY"   
         fi
         
         printf "\n${WEBCLIENT_KEY}${NORMAL}\n\n"               

         exit
      fi
   fi
   
   echo $'\n'"Backup certificate and private key:"
   
   backupVECSCertKey "machine"
   backupVECSCertKey "vsphere-webclient"
   
   if [ $NODE_TYPE != "infrastructure" ]; then
      backupVECSCertKey "vpxd"            
      backupVECSCertKey "vpxd-extension"
      
      if [[ "$VC_VERSION" =~ ^7 ]]; then 
         backupVECSCertKey "wcp"
         backupVECSCertKey "hvc"      
      fi
   fi
   
   echo $'\n'"Updating certificates and keys in VECS:"
   
   updateVECS "machine"
   updateVECS "vsphere-webclient"
   
   if [ $NODE_TYPE != "infrastructure" ]; then
      updateVECS "vpxd"
      updateVECS "vpxd-extension"
      
      if [[ "$VC_VERSION" =~ ^7 ]]; then 
         updateVECS "wcp"
         updateVECS "hvc"
      fi
   fi

   echo $'\n'"Updating solution user certificates in VMDir:"
   replaceSolutionUserCert "machine" $MACHINE_CERT
   replaceSolutionUserCert "vsphere-webclient" $WEBCLIENT_CERT

   if [ $NODE_TYPE != "infrastructure" ]; then
      replaceSolutionUserCert "vpxd" $VPXD_CERT
      replaceSolutionUserCert "vpxd-extension" $VPXD_EXT_CERT
      if [[ "$VC_VERSION" =~ ^7 ]]; then 
         replaceSolutionUserCert "wcp" $WCP_CERT
         replaceSolutionUserCert "hvc" $HVC_CERT
      fi
   fi   
   
   echo ""
   
   task "Update certificates on filesystem"
   if [ $NODE_TYPE != "infrastructure" ]; then
      mv /etc/vmware-vpx/ssl/vcsoluser.crt /etc/vmware-vpx/ssl/vcsoluser.crt.old >> $LOG 2>&1 || errorMessage "Unable to backup the vpxd solution user certificate"
      mv /etc/vmware-vpx/ssl/vcsoluser.key /etc/vmware-vpx/ssl/vcsoluser.key.old >> $LOG 2>&1 || errorMessage "Unable to backup the vpxd solution user private key"
      cp $VPXD_CERT /etc/vmware-vpx/ssl/vcsoluser.crt >> $LOG 2>&1 || errorMessage "Unable to update the vpxd solution user certificate"
      cp $VPXD_KEY /etc/vmware-vpx/ssl/vcsoluser.key >> $LOG 2>&1 || errorMessage "Unable to update the vpxd solution user private key"
      chown root:cis /etc/vmware-vpx/ssl/vcsoluser.*

      mv /etc/vmware-rbd/ssl/waiter.crt /etc/vmware-rbd/ssl/waiter.crt.old >> $LOG 2>&1 || errorMessage "Unable to backup the Auto Deploy waiter certificate"
      mv /etc/vmware-rbd/ssl/waiter.key /etc/vmware-rbd/ssl/waiter.key.old >> $LOG 2>&1 || errorMessage "Unable to backup the Auto Deploy waiter private key"
      cp $VPXD_EXT_CERT /etc/vmware-rbd/ssl/waiter.crt >> $LOG 2>&1 || errorMessage "Unable to update the Auto Deploy waiter certificate"
      cp $VPXD_EXT_KEY /etc/vmware-rbd/ssl/waiter.key >> $LOG 2>&1 || errorMessage "Unable to update the Auto Deploy waiter private key"
      chown deploy:deploy /etc/vmware-rbd/ssl/waiter.*
   fi

   taskMessage "OK" "GREEN"
}

#------------------------------
# Replace a Solution User certificate in VMDir
#------------------------------
function replaceSolutionUserCert() {
   task $1
   $DIR_CLI service update --name $1-$MACHINE_ID --cert $2 --login $VMDIR_USER_UPN --password "$(cat $STAGE_DIR/.vmdir-user-password)" >> $LOG 2>&1 || errorMessage "Unable to update $1-$MACHINE_ID solution user certificate in VMDir"
   taskMessage "OK" "GREEN"
}

#------------------------------
# Replace the Authentication Proxy certificate
#------------------------------
function replaceAuthProxyCert() {
   header "Replace Authentication Proxy Certificate"

   if [ $AUTH_PROXY_REPLACE = "VMCA-SIGNED" ]; then
      getPSCLocation
      
      generateAuthProxyCertoolConfig
      
      task "Regenerate Authentication Proxy certificate"
      regenerateSelfSignedCertificate "auth-proxy"
      taskMessage "OK" "GREEN"
          
      AUTH_PROXY_CERT=$STAGE_DIR/auth-proxy.crt
      AUTH_PROXY_KEY=$STAGE_DIR/auth-proxy.key
   else
      echo ""
      echo "1. Generate Certificate Signing Request and Private Key" | tee -a $LOG
      echo "2. Import CA-signed certificate and key" | tee -a $LOG
      echo ""
      read -p "Choose option [1]: " AUTH_PROXY_CA_SIGNED_OPTION
          
      if [ "$AUTH_PROXY_CA_SIGNED_OPTION" == "2" ]; then
         echo ""
         read -p "Provide path to CA-signed ${CYAN}Authentication Proxy${NORMAL} certificate: " AUTH_PROXY_CERT_INPUT
         while [ ! -f "$AUTH_PROXY_CERT_INPUT" ]; do read -p "${YELLOW}File not found, please provide path to the ${RED}Authentication Proxy${YELLOW} certificate:${NORMAL} " AUTH_PROXY_CERT_INPUT; done
         AUTH_PROXY_CERT=$(getCorrectCertFormat "$AUTH_PROXY_CERT_INPUT")
         read -p "Provide path to the ${CYAN}Authentication Proxy${NORMAL} private key: " AUTH_PROXY_KEY_INPUT
         while [ ! -f "$AUTH_PROXY_KEY_INPUT" ]; do read -p "${YELLOW}File not found, please provide path to the ${RED}Authentication Proxy${YELLOW} private key:${NORMAL} " AUTH_PROXY_KEY_INPUT; done
         AUTH_PROXY_KEY=$(getCorrectKeyFormat "$AUTH_PROXY_KEY_INPUT")
         
         getCAChain "$AUTH_PROXY_CERT" 
         
         task "Verifying certificates and keys: "
         verifyCertAndKey $AUTH_PROXY_CERT $AUTH_PROXY_KEY
      else
         AUTH_PROXY_CSR=$REQUEST_DIR/auth-proxy-$TIMESTAMP.csr
         AUTH_PROXY_KEY=$REQUEST_DIR/auth-proxy-$TIMESTAMP.key
         AUTH_PROXY_CFG=$REQUEST_DIR/auth-proxy.cfg
                 
         if [ -z $CSR_COUNTRY ]; then getCSRInfo; fi
                 
         generateOpensslConfig $HOSTNAME $AUTH_PROXY_CFG "Authentication Proxy"
         generateCSR $AUTH_PROXY_CSR $AUTH_PROXY_KEY $AUTH_PROXY_CFG

         printf "\nCertificate Signing Request generated at ${CYAN}${AUTH_PROXY_CSR}${NORMAL}"
         printf "\nPrivate Key generated at ${CYAN}${AUTH_PROXY_KEY}${NORMAL}"

         return 0
      fi
   fi   

   if [ $AUTH_PROXY_REPLACE != "VMCA-SIGNED" ]; then
      task "Pubish CA signing certificates"
      $DIR_CLI trustedcert publish --chain --cert $TRUSTED_ROOT_CHAIN --login $VMDIR_USER_UPN --password "$(cat $STAGE_DIR/.vmdir-user-password)" >> $LOG 2>&1 || errorMessage "Unable to publish trusted root chain to VMDir"
      taskMessage "OK" "GREEN"
   fi
   
   
   if [ -f /var/lib/vmware/vmcam/ssl/rui.crt ] && [ -f /var/lib/vmware/vmcam/ssl/rui.key ]; then backupFilesystemCertKey "/var/lib/vmware/vmcam/ssl/rui.crt" "/var/lib/vmware/vmcam/ssl/rui.crt" "auth-proxy"; fi
   
   task "Replace certificate on filesystem"
   mv /var/lib/vmware/vmcam/ssl/vmcamcert.pem /var/lib/vmware/vmcam/ssl/vmcamcert.pem.old >> $LOG 2>&1 || errorMessage "Unable to backup Authentication Proxy PEM file"
   
   cp $AUTH_PROXY_CERT /var/lib/vmware/vmcam/ssl/rui.crt >> $LOG 2>&1 || errorMessage "Unable to update Authentication Proxy certificate"
   cp $AUTH_PROXY_KEY /var/lib/vmware/vmcam/ssl/rui.key >> $LOG 2>&1 || errorMessage "Unable to update Authentication Proxy private key"
   cat /var/lib/vmware/vmcam/ssl/rui.key <(echo) /var/lib/vmware/vmcam/ssl/rui.crt > /var/lib/vmware/vmcam/ssl/vmcamcert.pem 2>&1 || errorMessage "Unable to update Authentication Proxy PEM file"
   chmod 600 /var/lib/vmware/vmcam/ssl/*
   taskMessage "OK" "GREEN"

   return 0
}

#------------------------------
# Replace the Auto Deploy CA certificate
#------------------------------
function replaceAutoDeployCACert() {
   header "Replace Auto Deploy CA Certificate"
   if [ $AUTO_DEPLOY_CA_REPLACE == "SELF-SIGNED" ]; then
      task "Regenerate Auto Deploy CA certificate"
      openssl req -new -newkey rsa:2048 -nodes -keyout $STAGE_DIR/auto-deploy-ca.key -x509 -out $STAGE_DIR/auto-deploy-ca.crt -subj "/O=VMware Auto Deploy" -days 3650 >> $LOG 2>&1 || errorMessage "Unable to generate new Auto Deploy CA certificate and private key. See log for details."
      taskMessage "OK" "GREEN"
      AUTO_DEPLOY_CA_CERT=$STAGE_DIR/auto-deploy-ca.crt
      AUTO_DEPLOY_CA_KEY=$STAGE_DIR/auto-deploy-ca.key        
   else
      echo $'\n'"1. Generate Certificate Signing Request and Private Key" | tee -a $LOG
      echo "2. Import CA-signed certificate and key" | tee -a $LOG
      read -p $'\n'"Choose option [1]: " AUTO_DEPLOY_CA_CA_SIGNED_OPTION
      
      if [ "$AUTO_DEPLOY_CA_CA_SIGNED_OPTION" == "2" ]; then
         echo "User has chosen to import a CA-signed Auto Deploy certificate and key" >> $LOG
         read -p $'\n'"Provide path to CA-signed ${CYAN}Auto Deploy CA${NORMAL} certificate: " AUTO_DEPLOY_CA_CERT_INPUT
         while [ ! -f "$AUTO_DEPLOY_CA_CERT_INPUT" ]; do read -p "${YELLOW}File not found, please provide path to the ${RED}Auto Deploy CA${YELLOW} certificate:${NORMAL} " AUTO_DEPLOY_CA_CERT_INPUT; done
         AUTO_DEPLOY_CA_CERT=$(getCorrectCertFormat "$AUTO_DEPLOY_CA_CERT_INPUT")
         read -p "Provide path to the ${CYAN}Auto Deploy CA${NORMAL} private key: " AUTO_DEPLOY_CA_KEY_INPUT
         while [ ! -f "$AUTO_DEPLOY_CA_KEY_INPUT" ]; do read -p "${YELLOW}File not found, please provide path to the ${RED}Auto Deploy CA${YELLOW} private key:${NORMAL} " AUTO_DEPLOY_CA_KEY_INPUT; done
         AUTO_DEPLOY_CA_KEY=$(getCorrectKeyFormat "$AUTO_DEPLOY_CA_KEY_INPUT")
         
         getCAChain "$AUTO_DEPLOY_CERT"  
         
         task "Verifying certificates and keys: "
         verifyCertAndKey $AUTO_DEPLOY_CA_CERT $AUTO_DEPLOY_CA_KEY
         
         task "Verifying CA certificate: "
         isCertCA "$(cat $AUTO_DEPLOY_CA_CERT)" || errorMessage "The provided certificate ${VMCA_CERT} is not a CA certificate."
         taskMessage "OK" "GREEN"
      else
         AUTO_DEPLOY_CA_CSR=$REQUEST_DIR/auto-deploy-ca-$TIMESTAMP.csr
         AUTO_DEPLOY_CA_KEY=$REQUEST_DIR/auto-deploy-ca-$TIMESTAMP.key
         AUTO_DEPLOY_CA_CFG=$REQUEST_DIR/auto-deploy-ca.cfg
         
         if [ -z $CSR_COUNTRY ]; then getCSRInfo; fi
         
         generateOpensslConfig $HOSTNAME $AUTO_DEPLOY_CA_CFG "Auto Deploy"
         generateCSR $AUTO_DEPLOY_CA_CSR $AUTO_DEPLOY_CA_KEY $AUTO_DEPLOY_CA_CFG
         
         printf "\n\nCertificate Signing Request generated at ${CYAN}${AUTO_DEPLOY_CA_CFG}${NORMAL}"
         printf "\nPrivate Key generated at ${CYAN}${AUTO_DEPLOY_CA_KEY}${NORMAL}\n\n"

         return 0
      fi
   fi
   
   if [ $AUTO_DEPLOY_CA_REPLACE != "SELF-SIGNED" ]; then
      task "Pubish CA signing certificates"
      $DIR_CLI trustedcert publish --chain --cert $TRUSTED_ROOT_CHAIN --login $VMDIR_USER_UPN --password "$(cat $STAGE_DIR/.vmdir-user-password)" >> $LOG 2>&1 || errorMessage "Unable to publish trusted root chain to VMDir"
      taskMessage "OK" "GREEN"
   fi
   
   backupFilesystemCertKey "/etc/vmware-rbd/ssl/rbd-ca.crt" "/etc/vmware-rbd/ssl/rbd-ca.key" "auto-deploy-ca"
   
   task "Replace certificate on filesystem"
   cp $AUTO_DEPLOY_CA_CERT /etc/vmware-rbd/ssl/rbd-ca.crt >> $LOG 2>&1 || errorMessage "Unable to update Auto Deploy CA certificate"
   cp $AUTO_DEPLOY_CA_KEY /etc/vmware-rbd/ssl/rbd-ca.key >> $LOG 2>&1 || errorMessage "Unable to update Auto Deploy CA private key"
   taskMessage "OK" "GREEN"
   
   return 0
}

#------------------------------
# Replace the VMDir certificate
#------------------------------
function replaceVMDirCert() {
   header "Replace VMware Directory Service Certificate"
   if [ $VMDIR_REPLACE == "VMCA-SIGNED" ]; then
      getPSCLocation

      generateVmdirCertoolConfig
      
      task "Regenerate VMware Directory certificate"
      regenerateSelfSignedCertificate "vmdir"
      taskMessage "OK" "GREEN"

      VMDIR_CERT=$STAGE_DIR/vmdir.crt
      VMDIR_KEY=$STAGE_DIR/vmdir.key
   else
      echo $'\n'"1. Generate Certificate Signing Request and Private Key" | tee -a $LOG
      echo "2. Import CA-signed certificate and key" | tee -a $LOG
      read -p $'\n'"Choose option [1]: " VMDIR_CA_SIGNED_OPTION

      if [ "${VMDIR_CA_SIGNED_OPTION}" == "2" ]; then
         echo "User has chosen to import a CA-signed VMware Directory certificate and key" >> $LOG
         read -p $'\n'"Provide path to CA-signed ${CYAN}VMware Directory Service${NORMAL} certificate: " VMDIR_CERT_INPUT
         while [ ! -f "$VMDIR_CERT_INPUT" ]; do read -p "${YELLOW}File not found, please provide path to the ${RED}VMware Directory Service${YELLOW} certificate:${NORMAL} " VMDIR_CERT_INPUT; done
         VMDIR_CERT=$(getCorrectCertFormat "$VMDIR_CERT_INPUT")
         read -p "Provide path to the ${CYAN}VMware Directory Service${NORMAL} private key: " VMDIR_KEY_INPUT
         while [ ! -f "$VMDIR_KEY_INPUT" ]; do read -p "${YELLOW}File not found, please provide path to the ${RED}VMware Directory Service${YELLOW} private key:${NORMAL} " VMDIR_KEY_INPUT; done
         VMDIR_KEY=$(getCorrectKeyFormat "$VMDIR_KEY_INPUT")
         
         getCAChain "$VMDIR_CERT"            
         
         task "Verifying certificates and keys: "
         verifyCertAndKey $VMDIR_CERT $VMDIR_KEY
      else
         VMDIR_CSR=$REQUEST_DIR/vmdir-$TIMESTAMP.csr
         VMDIR_KEY=$REQUEST_DIR/vmdir-$TIMESTAMP.key
         VMDIR_CFG=$REQUEST_DIR/vmdir.cfg

         if [ -z $CSR_COUNTRY ]; then getCSRInfo; fi
 
         generateOpensslConfig $HOSTNAME $VMDIR_CFG "vmdir"
         generateCSR $VMDIR_CSR $VMDIR_KEY $VMDIR_CFG

         printf "\n\nCertificate Signing Request generated at ${CYAN}${VMDIR_CSR}${NORMAL}"
         printf "\nPrivate Key generated at ${CYAN}${VMDIR_KEY}${NORMAL}\n\n"

         exit
      fi
   fi

   if [ $VMDIR_REPLACE != "VMCA-SIGNED" ]; then
      task "Pubish CA signing certificates"
      $DIR_CLI trustedcert publish --chain --cert $TRUSTED_ROOT_CHAIN --login $VMDIR_USER_UPN --password "$(cat $STAGE_DIR/.vmdir-user-password)" >> $LOG 2>&1 || errorMessage "Unable to publish trusted root chain to VMDir"
      taskMessage "OK" "GREEN"
   fi

   backupFilesystemCertKey "/usr/lib/vmware-vmdir/share/config/vmdircert.pem" "/usr/lib/vmware-vmdir/share/config/vmdirkey.pem" "VMDir"

   task "Replace certificate on filesystem"
   cp $VMDIR_CERT /usr/lib/vmware-vmdir/share/config/vmdircert.pem >> $LOG 2>&1 || errorMessage "Unable to update VMware Directory Services certificate"
   cp $VMDIR_KEY /usr/lib/vmware-vmdir/share/config/vmdirkey.pem >> $LOG 2>&1 || errorMessage "Unable to update VMware Directory Services private key"
   taskMessage "OK" "GREEN"
}

#------------------------------
# Add new STS signing certificate
#------------------------------
function replaceSSOSTSCert() {
   header "Replace SSO STS Signing Certificate"
   getPSCLocation
   generateSSOSTSCertoolConfig
   
   task "Regenerate STS signing certificate"
   regenerateSelfSignedCertificate "sso-sts"
   taskMessage "OK" "GREEN"

   task "Backup and delete existing tenant entries"
   TENANTS=$($LDAP_SEARCH -h $VMDIR_FQDN -p 389 -b "cn=$SSO_DOMAIN,cn=Tenants,cn=IdentityManager,cn=Services,$VMDIR_DOMAIN_DN" -D "cn=$VMDIR_USER,cn=users,$VMDIR_DOMAIN_DN" -y $STAGE_DIR/.vmdir-user-password "(objectclass=vmwSTSTenantCredential)" | grep numEntries | awk '{print $3}')

   i=1
   if [ ! -z $TENANTS ]; then
      until [ $i -gt $TENANTS ]; do      
        $LDAP_SEARCH -h $VMDIR_FQDN -D "cn=${VMDIR_USER},cn=users,${VMDIR_DOMAIN_DN}" -y $STAGE_DIR/.vmdir-user-password -b "cn=TenantCredential-$i,cn=$SSO_DOMAIN,cn=Tenants,cn=IdentityManager,cn=Services,$VMDIR_DOMAIN_DN" > $BACKUP_DIR/tenantcredential-$i.ldif
        $LDAP_SEARCH -h $VMDIR_FQDN -D "cn=${VMDIR_USER},cn=users,${VMDIR_DOMAIN_DN}" -y $STAGE_DIR/.vmdir-user-password -b "cn=TrustedCertChain-$i,cn=TrustedCertificateChains,cn=$SSO_DOMAIN,cn=Tenants,cn=IdentityManager,cn=Services,$VMDIR_DOMAIN_DN" > $BACKUP_DIR/trustedcertchain-$i.ldif
        $LDAP_DELETE -h $VMDIR_FQDN -D "cn=${VMDIR_USER},cn=users,${VMDIR_DOMAIN_DN}" -y $STAGE_DIR/.vmdir-user-password "cn=TenantCredential-$i,cn=${SSO_DOMAIN},cn=Tenants,cn=IdentityManager,cn=Services,$VMDIR_DOMAIN_DN" | tee -a $LOG
        $LDAP_DELETE -h $VMDIR_FQDN -D "cn=${VMDIR_USER},cn=users,${VMDIR_DOMAIN_DN}" -y $STAGE_DIR/.vmdir-user-password "cn=TrustedCertChain-$i,cn=TrustedCertificateChains,cn=$SSO_DOMAIN,cn=Tenants,cn=IdentityManager,cn=Services,$VMDIR_DOMAIN_DN" | tee -a $LOG
        ((i++))
      done
   fi
   
   taskMessage "OK" "GREEN"

   task "Add new STS signing certifcate to VMDir"
   if [ -z $VMCA_CERT ]; then VMCA_CERT="/var/lib/vmware/vmca/root.cer"; fi

   openssl x509 -outform der -in $STAGE_DIR/sso-sts.crt -out $STAGE_DIR/sso-sts.der 2>/dev/null || errorMessage "Unable to create binary SSO STS certificate"
   openssl x509 -outform der -in $VMCA_CERT -out $STAGE_DIR/vmca.der 2>/dev/null || errorMessage "Unable to create binary VMCA certificate"
   openssl pkcs8 -topk8 -inform pem -outform der -in $STAGE_DIR/sso-sts.key -out $STAGE_DIR/sso-sts.key.der -nocrypt 2>/dev/null || errorMessage "Unable to create binary SSO STS private key"
   
   VMCA_CERTS=$(csplit -z -f $STAGE_DIR/vmca-cert- -b %02d.crt /var/lib/vmware/vmca/root.cer '/-----BEGIN CERTIFICATE-----/' '{*}' | wc -l)
   i=0
   until [ $i -eq $VMCA_CERTS ]; do
      openssl x509 -outform der -in $STAGE_DIR/vmca-cert-0$i.crt -out $STAGE_DIR/vmca-cert-0$i.der 2>/dev/null
      ((i++))
   done
   

   echo "dn: cn=TenantCredential-1,cn=$SSO_DOMAIN,cn=Tenants,cn=IdentityManager,cn=Services,$VMDIR_DOMAIN_DN" > $STAGE_DIR/sso-sts.ldif
   echo "changetype: add" >> $STAGE_DIR/sso-sts.ldif
   echo "objectClass: vmwSTSTenantCredential" >> $STAGE_DIR/sso-sts.ldif
   echo "objectClass: top" >> $STAGE_DIR/sso-sts.ldif
   echo "cn: TenantCredential-1" >> $STAGE_DIR/sso-sts.ldif
   echo "userCertificate:< file://$STAGE_DIR/sso-sts.der" >> $STAGE_DIR/sso-sts.ldif
   
   i=0
   until [ $i -eq $VMCA_CERTS ]; do
      echo "userCertificate:< file:$STAGE_DIR/vmca-cert-0${i}.der" >> $STAGE_DIR/sso-sts.ldif
      ((i++))
   done
   
   echo "vmwSTSPrivateKey:< file://$STAGE_DIR/sso-sts.key.der" >> $STAGE_DIR/sso-sts.ldif
   echo "" >> $STAGE_DIR/sso-sts.ldif
   echo "dn: cn=TrustedCertChain-1,cn=TrustedCertificateChains,cn=$SSO_DOMAIN,cn=Tenants,cn=IdentityManager,cn=Services,$VMDIR_DOMAIN_DN" >> $STAGE_DIR/sso-sts.ldif
   echo "changetype: add" >> $STAGE_DIR/sso-sts.ldif
   echo "objectClass: vmwSTSTenantTrustedCertificateChain" >> $STAGE_DIR/sso-sts.ldif
   echo "objectClass: top" >> $STAGE_DIR/sso-sts.ldif
   echo "cn: TenantCredential-1" >> $STAGE_DIR/sso-sts.ldif
   echo "userCertificate:< file://$STAGE_DIR/sso-sts.der" >> $STAGE_DIR/sso-sts.ldif
   
   i=0
   until [ $i -eq $VMCA_CERTS ]; do
      echo "userCertificate:< file:$STAGE_DIR/vmca-cert-0$i.der" >> $STAGE_DIR/sso-sts.ldif
      ((i++))
   done

   $LDAP_MODIFY -v -h $VMDIR_FQDN -p 389 -D "$VMDIR_MACHINE_ACCOUNT_DN" -y $STAGE_DIR/.machine-account-password -f $STAGE_DIR/sso-sts.ldif >> $LOG 2>&1

   taskMessage "OK" "GREEN"
}

#------------------------------
# Generate a VMCA-signed certificate
#------------------------------
function regenerateSelfSignedCertificate() {
   $CERTOOL --genkey --privkey=$STAGE_DIR/$1.key --pubkey=$STAGE_DIR/$1.pub --server=$PSC_LOCATION >> $LOG 2>&1 || errorMessage "Unable to genereate new keys for ${1}"
   $CERTOOL --gencert --privkey=$STAGE_DIR/$1.key --cert=$STAGE_DIR/$1.crt --config=$STAGE_DIR/$1.cfg --server=$PSC_LOCATION  >> $LOG 2>&1 || errorMessage "Unable to generate self-signed certificate for ${1}"
}

#------------------------------
# Replace certificate in VECS
#------------------------------
function updateVECS() {
   case $1 in
      machine-ssl)
         VECS_STORE="MACHINE_SSL_CERT"
         VECS_ALIAS="__MACHINE_CERT"
         VECS_CERT_FILE=$MACHINE_SSL_CERT
         VECS_KEY_FILE=$MACHINE_SSL_KEY
         ;;
      legacy-lookup-service)
         VECS_STORE="STS_INTERNAL_SSL_CERT"
         VECS_ALIAS="__MACHINE_CERT"
         VECS_CERT_FILE=$MACHINE_SSL_CERT
         VECS_KEY_FILE=$MACHINE_SSL_KEY
         ;;
      machine)
         VECS_STORE=$1
         VECS_ALIAS=$1
         VECS_CERT_FILE=$MACHINE_CERT
         VECS_KEY_FILE=$MACHINE_KEY
         ;;
      vpxd)
         VECS_STORE=$1
         VECS_ALIAS=$1
         VECS_CERT_FILE=$VPXD_CERT
         VECS_KEY_FILE=$VPXD_KEY
         ;;
      vpxd-extension)
         VECS_STORE=$1
         VECS_ALIAS=$1
         VECS_CERT_FILE=$VPXD_EXT_CERT
         VECS_KEY_FILE=$VPXD_EXT_KEY
         ;;
      vsphere-webclient)
         VECS_STORE=$1
         VECS_ALIAS=$1
         VECS_CERT_FILE=$WEBCLIENT_CERT
         VECS_KEY_FILE=$WEBCLIENT_KEY
         ;;
      wcp)
         VECS_STORE=$1
         VECS_ALIAS=$1
         VECS_CERT_FILE=$WCP_CERT
         VECS_KEY_FILE=$WCP_KEY
         ;;
      hvc)
         VECS_STORE=$1
         VECS_ALIAS=$1
         VECS_CERT_FILE=$HVC_CERT
         VECS_KEY_FILE=$HVC_KEY
         ;;
   esac
   
   if [ "$1" == "machine-ssl" ]; then
      task "Updating ${VECS_STORE} certificate"
   else
      task "$1"
   fi
   $VECS_CLI entry delete --store $VECS_STORE --alias $VECS_ALIAS -y >> $LOG 2>&1 || errorMessage "Unable to delete entry ${VECS_ALIAS} in the VECS store $VECS_STORE"
   $VECS_CLI entry create --store $VECS_STORE --alias $VECS_ALIAS --cert $VECS_CERT_FILE --key $VECS_KEY_FILE >> $LOG 2>&1 || errorMessage "Unable to create entry $VECS_ALIAS in VECS store $VECS_STORE"
   taskMessage "OK" "GREEN"
}

#------------------------------
# Clear out the BACKUP_STORE in VECS
#------------------------------
function clearBackupStoreVECS() {
   header "Removing BACKUP_STORE entries from VECS"
   for alias in $($VECS_CLI entry list --store BACKUP_STORE | grep Alias | awk '{print $NF}'); do
      task "Backing up $alias"
      $VECS_CLI entry getcert --store BACKUP_STORE --alias $alias > $BACKUP_DIR/$alias.crt >> $LOG || errorMessage "Unable to backup $alias certificate"
      $VECS_CLI entry getkey --store BACKUP_STORE --alias $alias > $BACKUP_DIR/$alias.key >> $LOG || errorMessage "Unable to backup $alias private key"
      taskMessage "OK" "GREEN"
      
      task "Deleting $alias"
      $VECS_CLI entry delete --store BACKUP_STORE --alias $alias -y >> $LOG 2>&1 || errorMessage "Unable to delete the BACKUP_STORE entry $alias"
      taskMessage "OK" "GREEN"
   done
}

#------------------------------
# Restart reverse proxy
#------------------------------
function restartReverseProxy() {
   header "Restarting Reverse Proxy service"
   task "Restarting service"
   service-control --stop vmware-rhttpproxy 2>&1 >> $LOG && service-control --start vmware-rhttpproxy 2>&1 >> $LOG 
   if [ $(service-control --status vmware-rhttpproxy | head -n1) == "Running:" ]; then
      taskMessage "OK" "GREEN"
   else
      taskMessage "ERROR" "YELLOW"
   fi
}

#------------------------------
# Restart VMware services
#------------------------------
function restartVMwareServices() {
   header "Restarting Services"
   
   task "Stopping VMware services"
   service-control --stop --all >> $LOG 2>&1 || errorMessage "Unable to stop all VMware services, check log for details."
   taskMessage "OK" "GREEN"
   
   task "Starting VMware services"
   service-control --start --all >> $LOG 2>&1 || errorMessage "Unable to start all VMware services, check log for details."
   taskMessage "OK" "GREEN"
  
   if [[ "$VC_VERSION" =~ ^6 ]]; then
      task "Restarting VAMI service"
      systemctl restart vami-lighttp
      if [ $(systemctl status vami-lighttp | grep 'Active:' | awk '{print $3}') == "(running)" ]; then
         taskMessage "OK" "GREEN"
      else
         taskMessage "ERROR" "YELLOW"
      fi
   fi
   if [[ $UPDATED_MACHINE_SSL -eq 1 || $UPDATED_TRUST_ANCHORS -eq 1 ]] && [ "$NODE_TYPE" != "embedded" ]; then
      printf "\n\n${YELLOW}Please restart services on all other vCenter/PSC nodes in this environment.${NORMAL}\n\n"
   fi
}

#------------------------------
# List all certificates used as SSL trust anchors
#------------------------------
function checkSSLTrustAnchors() {
   header "Check SSL Trust Anchors"
   CERT_HASHES=()
   CERT_COUNT=1

   echo "Additional output options:"
   echo " 1. None"
   echo " 2. Show associated Service IDs"
   echo " 3. Show associated endpoint URIs"
   echo " 4. Show both associated Service IDs and endpoint URIs"
   echo " 5. Show the SHA256 fingerprint of the certificates"

   read -p $'\n'"Please select additional information options [1]: " CHECK_TRUST_ANCHOR_OUTPUT_OPTIONS
   
   if [[ "$CHECK_TRUST_ANCHOR_OUTPUT_OPTIONS" -eq 5 ]]; then
      TP_ALGORITHM="sha256"
      TP_REGEX_ITER="31"
   else
      TP_ALGORITHM="sha1"
      TP_REGEX_ITER="19"
   fi

   $LDAP_SEARCH -LLL -h ${VMDIR_FQDN} -p 389 -b "cn=Sites,cn=Configuration,$VMDIR_DOMAIN_DN" -D "cn=$VMDIR_USER,cn=users,$VMDIR_DOMAIN_DN" -y $STAGE_DIR/.vmdir-user-password "(|(objectclass=vmwLKUPEndpointRegistration)(objectclass=vmwLKUPServiceEndpoint))" vmwLKUPEndpointSslTrust vmwLKUPSslTrustAnchor vmwLKUPURI > $STAGE_DIR/trust-anchors.raw

   TRUST_ANCHORS=$(cat $STAGE_DIR/trust-anchors.raw | tr -d '\n' | tr -d ' ' | sed -e 's|vmwLKUPEndpointSslTrust|\n&|g' -e 's|vmwLKUPSslTrustAnchor|\n&|g' -e 's|vmwLKUPURI|\n&|g' -e 's|dn:|\n&|g'| grep -vE '^dn:|^vmwLKUPURI' | grep '^vmwLKUP' | sed -e 's|vmwLKUPEndpointSslTrust||g' -e 's|vmwLKUPSslTrustAnchor||g' -e 's|:||g' | sort | uniq)

   for cert in $TRUST_ANCHORS; do 
      if [[ "$cert" =~ ^TUl ]]; then
         CURRENT_CERT=$(echo $cert | base64 --decode | tr -d '\r\n')
      else
         CURRENT_CERT=($cert)
      fi
      if [[ ! "${CERT_HASHES[@]}" =~ "$CURRENT_CERT" ]]; then
         CERT_HASHES+=($CURRENT_CERT)
      fi
   done

   printf "\n"
   for hash in "${CERT_HASHES[@]}"; do
      echo "${CYAN}-----Endpoint Certificate ${CERT_COUNT}-----${NORMAL}" 
      TEMP_CERT="-----BEGIN CERTIFICATE-----"$'\n'
      TEMP_CERT+=$(echo $hash | fold -c64)
      TEMP_CERT+=$'\n'"-----END CERTIFICATE-----"
      if echo "${TEMP_CERT}" | openssl x509 -noout -checkend 0 2>/dev/null; then
         DATE_COLOR="NORMAL"
      else
         DATE_COLOR="RED"
      fi
      echo "$TEMP_CERT" | openssl x509 -text -noout -fingerprint -$TP_ALGORITHM 2>/dev/null | grep -E 'Issuer:|Subject:|Validity|Not Before:|Not After :|Fingerprint' | sed -e "s/Not Before/${!DATE_COLOR}&/" -e 's/SHA[0-9]* Fingerprint/\t&/g' -e "s/Subject:/${GREEN}&${NORMAL}/g" -e "s/[[:xdigit:]]\{2\}\(:[[:xdigit:]]\{2\}\)\{${TP_REGEX_ITER}\}/${YELLOW}&${NORMAL}/g"
      
      if [[ "${CHECK_TRUST_ANCHOR_OUTPUT_OPTIONS}" -eq 2 || "${CHECK_TRUST_ANCHOR_OUTPUT_OPTIONS}" -eq 4 ]]; then
         USED_BY_SERVICE_IDS=$(cat $STAGE_DIR/trust-anchors.raw | tr -d '\n' | tr -d ' ' | sed -e 's|vmwLKUPEndpointSslTrust|\n&|g' -e 's|vmwLKUPSslTrustAnchor|\n&|g' -e 's|dn:|\ndn:|g'| grep -B1 ${hash} | grep '^dn:' | awk -F',' '{print $2}' | tr -d 'cn=' | sort | uniq)

         double_encoded_hash=$(echo "$hash" | tr -d '\n' | sed -e 's/.\{76\}/&\r\n/g' | xargs -0 printf "%s\r\n" | base64 -w 0)

         USED_BY_SERVICE_IDS+=$'\n'$(cat $STAGE_DIR/trust-anchors.raw | tr -d '\n' | tr -d ' ' | sed -e 's|vmwLKUPEndpointSslTrust|\n&|g' -e 's|vmwLKUPSslTrustAnchor|\n&|g' -e 's|dn:|\ndn:|g'| grep -B1 ${double_encoded_hash} | grep '^dn:' | awk -F',' '{print $2}' | tr -d 'cn=' | sort | uniq | xargs -0 printf "\n%s")

         NUM_USED_BY_SERVICE_IDS=$(echo "$USED_BY_SERVICE_IDS" | grep -v '^$' | wc -l)
         echo "Used by $NUM_USED_BY_SERVICE_IDS service registrations:" | tee -a $LOG

         for service in $USED_BY_SERVICE_IDS; do
            echo $'\t'"$service" | tee -a $LOG
         done
      fi
      
      if [[ "$CHECK_TRUST_ANCHOR_OUTPUT_OPTIONS" -eq 3 || "$CHECK_TRUST_ANCHOR_OUTPUT_OPTIONS" -eq 4 ]]; then
         USED_BY_ENDPOINTS=$(cat $STAGE_DIR/trust-anchors.raw | tr -d '\n' | tr -d ' ' | sed -e 's|vmwLKUPEndpointSslTrust|\n&|g' -e 's|vmwLKUPSslTrustAnchor|\n&|g' -e 's|vmwLKUPURI|\n&|g' -e 's|dn:|\n&|g' | grep -v '^dn:' | grep -B1 ${hash} | grep '^vmwLKUPURI' | sed -e 's/vmwLKUPURI://g' | sort | uniq)
         
         double_encoded_hash=$(echo "$hash" | tr -d '\n' | sed -e 's/.\{76\}/&\r\n/g' | xargs -0 printf "%s\r\n" | base64 -w 0)
         
         USED_BY_ENDPOINTS+=$'\n'$(cat $STAGE_DIR/trust-anchors.raw | tr -d '\n' | tr -d ' ' | sed -e 's|vmwLKUPEndpointSslTrust|\n&|g' -e 's|vmwLKUPSslTrustAnchor|\n&|g' -e 's|vmwLKUPURI|\n&|g' -e 's|dn:|\n&|g' | grep -v '^dn:' | grep -B1 ${double_encoded_hash} | grep '^vmwLKUPURI' | sed -e 's/vmwLKUPURI://g' | sort | uniq)
         
         NUM_USED_BY_ENDPOINTS=$(echo "$USED_BY_ENDPOINTS" | grep -v '^$' | wc -l)
         
         echo "Used by $NUM_USED_BY_ENDPOINTS endpoints:" | tee -a $LOG
         
         for endpoint in $USED_BY_ENDPOINTS; do
            echo $'\t'"$endpoint" | tee -a $LOG
         done
      fi
      echo "${CYAN}--------------------------------${NORMAL}"
      ((++CERT_COUNT))
   done

   getSSODomainNodes
   
   echo ""
   for node in "${SSO_NODES[@]}"; do
      echo "${CYAN}-----Machine SSL Certificate-----${NORMAL}"
      echo "${CYAN}${node}${NORMAL}"
      CURRENT_MACHINE_SSL_CERT_INFO=$(echo | openssl s_client -connect $node:443 2>/dev/null | openssl x509 -text -noout -fingerprint -$TP_ALGORITHM 2>/dev/null | grep -E 'Issuer:|Subject:|Validity|Not Before:|Not After :|Fingerprint' | sed -e 's/SHA[0-9]* Fingerprint/\t&/g' -e "s/Subject:/${GREEN}&${NORMAL}/g" -e "s/[[:xdigit:]]\{2\}\(:[[:xdigit:]]\{2\}\)\{${TP_REGEX_ITER}\}/${YELLOW}&${NORMAL}/g")

      if [ ! -z "$CURRENT_MACHINE_SSL_CERT_INFO" ]; then
         echo "Certificate Info:"
         if echo | openssl s_client -connect $node:443 2>/dev/null | openssl x509 -noout -checkend 0 2>/dev/null; then
            echo "$CURRENT_MACHINE_SSL_CERT_INFO"
         else
            echo "$CURRENT_MACHINE_SSL_CERT_INFO" | sed -e "s/Not Before/${RED}&/"
         fi
      else
         echo "${YELLOW}Unable to get certificate from $node on port 443"
         echo "Please make sure the server is up and the reverse proxy service is running.$NORMAL"
      fi
      echo "${CYAN}---------------------------------${NORMAL}"
   done
}

#------------------------------
# Get the PSC and vCenter nodes in an SSO Domain
#------------------------------
function getSSODomainNodes() {
   SSO_NODES=()
   PSC_NODES=$($LDAP_SEARCH -LLL -h $VMDIR_FQDN -p 389 -b "ou=Domain Controllers,$VMDIR_DOMAIN_DN" -D "cn=$VMDIR_USER,cn=users,$VMDIR_DOMAIN_DN" -y $STAGE_DIR/.vmdir-user-password "(objectclass=computer)" cn | grep '^cn:' | awk '{print $2}')
   PSC_COUNT=$(echo "${PSC_NODES}" | wc -l)
   VCENTER_NODES=$($LDAP_SEARCH -LLL -h $VMDIR_FQDN -p 389 -b "ou=Computers,$VMDIR_DOMAIN_DN" -D "cn=$VMDIR_USER,cn=users,$VMDIR_DOMAIN_DN" -y $STAGE_DIR/.vmdir-user-password "(objectclass=computer)" cn | grep '^cn:' | awk '{print $2}')
   VCENTER_COUNT=$(echo "${VCENTER_NODES}" | wc -l)
   
   for psc_node in "$PSC_NODES"; do
      if [[ ! "${SSO_NODES[@]}" =~ "$psc_node" ]]; then SSO_NODES+=($psc_node); fi
   done

   for vc_node in "$VCENTER_NODES"; do
      if [[ ! "${SSO_NODES[@]}" =~ "$vc_node" ]]; then SSO_NODES+=($vc_node); fi
   done
}

#------------------------------
# Select which node to update SSL trust anchors
#------------------------------
function SSLTrustAnchorsSelectNode() {
   getSSODomainNodes
   
   NODE_COUNTER=1
   NODE_DEFAULT=1
   PSC_VIP_COUNTER=0   

   printf "\nNodes in SSO domain '$SSO_DOMAIN'\n" | tee -a $LOG
   
   for node in "${SSO_NODES[@]}"; do
      echo " $NODE_COUNTER. $node" | tee -a $LOG
      if [ $HOSTNAME = $node ]; then NODE_DEFAULT=$NODE_COUNTER; fi
      ((++NODE_COUNTER))
   done
   
   if [[ $VCENTER_COUNT -gt 0 && $PSC_COUNT -gt 1 ]]; then
      echo " $NODE_COUNTER. FQDN of PSC Load Balancer" | tee -a $LOG
      PSC_VIP_COUNTER=$NODE_COUNTER
   fi
   
   read -p $'\n'"Select node to update [${NODE_DEFAULT}]: " NODE_SELECT

   if [ -z $NODE_SELECT ]; then
      NODE_FQDN=${SSO_NODES[$((NODE_DEFAULT - 1))]}
   else
      if [[ $PSC_VIP_COUNTER -gt 0 && "${NODE_SELECT}" == "$PSC_VIP_COUNTER" ]]; then
         read -p "Enter the FQDN of the PSC Load Balancer: " PSC_LB_FQDN
         while [ -z $PSC_LB_FQDN ]; do
            read -p "Enter the FQDN of the PSC Load Balancer: " PSC_LB_FQDN
         done
         NODE_FQDN=$PSC_LB_FQDN
      else
         NODE_FQDN=${SSO_NODES[$((NODE_SELECT - 1))]}
      fi
   fi

   echo "User has selected '$NODE_FQDN'" >> $LOG

   echo "y" | openssl s_client -connect $NODE_FQDN:443 2>/dev/null | openssl x509 > $STAGE_DIR/trust-anchor-machine-ssl.crt 2>/dev/null
}

#------------------------------
# Setup environment to update SSL trust anchors for the current node
#------------------------------
function SSLTrustAnchorSelf() {
   openssl x509 -in $MACHINE_SSL_CERT >  $STAGE_DIR/trust-anchor-machine-ssl.crt 2>/dev/null
   NODE_FQDN="$PNID"
}

#------------------------------
# Update the SSL trust anchors
#------------------------------
function updateSSLTrustAnchors() {
   TOTAL_SERVICES_UPDATED=0
   header "Update SSL Trust Anchors"

   find $STAGE_DIR -type f -iname 'ls-service-reg-*.ldif' -exec rm {} \;

   if [ "$VMDIR_FQDN" != "$PNID" ]; then
      read -s -p $'\n'"Enter the root password for $PSC_LOCATION: " SSHPASS
      PSC_INFO=$(sshpass -p "$SSHPASS" ssh -q -o StrictHostKeyChecking=no -t -t root@$PSC_LOCATION "/opt/likewise/bin/lwregshell list_values '[HKEY_THIS_MACHINE\services\vmdir]' | grep -E 'dcAccountPassword|dcAccountDN'" | grep 'dcAccount')
      
      echo "PSC info is: $PSC_INFO" >> $LOG
      
      if [ -z "$PSC_INFO" ]; then
         echo $'\n\n'"${YELLOW}Unable to get machine account password for $PSC_LOCATION." | tee -a $LOG
         echo $'\n'"This is usually because the default shell on the PSC is /bin/appliancesh instead of /bin/bash" | tee -a $LOG
         echo $'\n'"Please change the default shell on $PSC_LOCATION," | tee -a $LOG
         echo "or run this script on $PSC_LOCATION to update the SSL trust anchors.${NORMAL}" | tee -a $LOG
         
         return 1
      fi
      
      UPDATE_MACHINE_PASSWORD=$(echo "$PSC_INFO" | grep 'dcAccountPassword' | awk -F"  " '{print $NF}' | awk '{print substr($0,2,length($0)-3)}' | sed -e 's/\\"/"/g' -e 's/\\\\/\\/g')
      UPDATE_MACHINE_ACCOUNT_DN=$(echo "$PSC_INFO" | grep 'dcAccountDN' | awk -F"  " '{print $NF}' | awk '{print substr($0,2,length($0)-3)}')
      printf "\n\n"
   else
      UPDATE_MACHINE_ACCOUNT_DN=$VMDIR_MACHINE_ACCOUNT_DN
      UPDATE_MACHINE_PASSWORD=$VMDIR_MACHINE_PASSWORD
   fi

   echo -n "$UPDATE_MACHINE_PASSWORD" > $STAGE_DIR/.update-machine-account-password
   chmod 640 $STAGE_DIR/.update-machine-account-password
   cat $STAGE_DIR/trust-anchor-machine-ssl.crt | grep -vE '^-----' | tr -d '\n' > $STAGE_DIR/trust-anchor-machine-ssl.hash
   openssl x509 -outform der -in $STAGE_DIR/trust-anchor-machine-ssl.crt -out $STAGE_DIR/trust-anchor-machine-ssl.der 2>/dev/null

   SERVICE_REGISTRATION_DNS=$($LDAP_SEARCH -LLL -h $VMDIR_FQDN -p 389 -b "cn=Sites,cn=Configuration,$VMDIR_DOMAIN_DN" -D "cn=$VMDIR_USER,cn=users,$VMDIR_DOMAIN_DN" -y $STAGE_DIR/.vmdir-user-password "(&(vmwLKUPURI=*$NODE_FQDN*)(|(objectclass=vmwLKUPServiceEndpoint)(objectclass=vmwLKUPEndpointRegistration)))" vmwLKUPEndpointSslTrust vmwLKUPSslTrustAnchor | tr -d '\n' | tr -d ' ' | sed  -e 's|vmwLKUP|\n&|g' -e 's|dn:|\ndn:|g' | grep '^dn:' | sed -r 's/cn=Endpoint[0-9]+,//g' | sed 's/dn://g' | sort | uniq)

   SSO_ALL_SITES=$($LDAP_SEARCH -LLL -h $VMDIR_FQDN -b "cn=Sites,cn=Configuration,$VMDIR_DOMAIN_DN" -D "cn=$VMDIR_USER,cn=users,$VMDIR_DOMAIN_DN" -y $STAGE_DIR/.vmdir-user-password -s one "(objectclass=*)" cn | tr -d ' ' | tr -d '\n' | sed -e 's/dn:/\n&/g' -e 's/cn:/\n&/g' | grep '^cn:' | awk -F':' '{print $NF}')

   for svc_dn in $SERVICE_REGISTRATION_DNS; do
      LEGACY_REGISTRATION=0
      
      for site in $SSO_ALL_SITES; do
         SVC_LOWER=$(echo "$svc_dn" | awk -F',' '{print $1}' | awk -F'=' '{print $2}' | tr '[:upper:]' '[:lower:]')
         SITE_LOWER=$(echo "$site" | tr '[:upper:]' '[:lower:]')
         if [[ $SVC_LOWER =~ ^$SITE_LOWER: ]]; then LEGACY_REGISTRATION=1; fi
      done
      
      if [ $LEGACY_REGISTRATION = 1 ]; then
         echo "Updating service $svc_dn" >> $LOG      
         update55SSLTrustAnchorTargeted $svc_dn
      else
         echo "Updating service $svc_dn" >> $LOG      
         update60SSLTrustAnchorTargeted $svc_dn
      fi
   done

   echo "Updated $TOTAL_SERVICES_UPDATED service(s)"

   UPDATED_TRUST_ANCHORS=1

   return 0
}

#------------------------------
# Update a legacy SSL trust anchor
#------------------------------
function update55SSLTrustAnchorTargeted() {
   SERVICE_DN=$1
   SERVICE_ID=$(echo "$SERVICE_DN" | awk -F',' '{print $1}' | awk -F'=' '{print $2}')
   
   ENDPOINT_INFO=$($LDAP_SEARCH -LLL -h $VMDIR_FQDN -p 389 -b "$SERVICE_DN" -D "cn=$VMDIR_USER,cn=users,$VMDIR_DOMAIN_DN" -y $STAGE_DIR/.vmdir-user-password "(|(objectclass=vmwLKUPServiceEndpoint)(objectclass=vmwLKUPEndpointRegistration))" vmwLKUPEndpointSslTrust vmwLKUPSslTrustAnchor | tr -d '\n' | tr -d ' ' | sed  -e 's|vmwLKUP|\n&|g' -e 's|dn:|\ndn:|g')

   for line in $ENDPOINT_INFO; do
      if [[ $line =~ ^dn: ]]; then
         CURRENT_DN=$line
      elif [[ $line =~ ^vmwLKUP ]]; then
         echo "$CURRENT_DN" >> $STAGE_DIR/ls-service-reg-$SERVICE_ID.ldif
         echo "changetype: modify" >> $STAGE_DIR/ls-service-reg-$SERVICE_ID.ldif
         if echo $line | grep 'vmwLKUPSslTrustAnchor' > /dev/null; then
            echo "replace: vmwLKUPSslTrustAnchor" >> $STAGE_DIR/ls-service-reg-$SERVICE_ID.ldif
            echo "vmwLKUPSslTrustAnchor:< file://$STAGE_DIR/trust-anchor-machine-ssl.der" >> $STAGE_DIR/ls-service-reg-$SERVICE_ID.ldif
         else
            echo "replace: vmwLKUPEndpointSslTrust" >> $STAGE_DIR/ls-service-reg-$SERVICE_ID.ldif
            echo "vmwLKUPEndpointSslTrust:< file://$STAGE_DIR/trust-anchor-machine-ssl.hash" >> $STAGE_DIR/ls-service-reg-$SERVICE_ID.ldif
         fi
         echo "" >> $STAGE_DIR/ls-service-reg-$SERVICE_ID.ldif
      fi
   done
   
   if [ -f $STAGE_DIR/ls-service-reg-$SERVICE_ID.ldif ]; then
      echo "Updating service: ${SERVICE_ID}" | tee -a $LOG
      if ! $LDAP_MODIFY -v -h $VMDIR_FQDN -p 389 -D "${UPDATE_MACHINE_ACCOUNT_DN}" -y $STAGE_DIR/.update-machine-account-password -f $STAGE_DIR/ls-service-reg-$SERVICE_ID.ldif >> $LOG 2>&1; then
         echo "Error updating service: please check logs for details"
      else
         ((++TOTAL_SERVICES_UPDATED))
      fi
   fi
}

#------------------------------
# Update an SSL trust anchor
#------------------------------
function update60SSLTrustAnchorTargeted() {
   SERVICE_DN=$1
   SERVICE_ID=$(echo "$SERVICE_DN" | awk -F',' '{print $1}' | awk -F'=' '{print $2}')
   ENDPOINT_INFO=$($LDAP_SEARCH -LLL -h $VMDIR_FQDN -p 389 -b "$SERVICE_DN" -D "cn=$VMDIR_USER,cn=users,$VMDIR_DOMAIN_DN" -y $STAGE_DIR/.vmdir-user-password "(objectclass=vmwLKUPEndpointRegistration)" vmwLKUPEndpointSslTrust | tr -d '\n' | tr -d ' ' | sed  -e 's|vmwLKUPEndpointSslTrust|\n&|g' -e 's|dn:|\ndn:|g')

   for line in $ENDPOINT_INFO; do
      if [[ $line =~ ^dn: ]]; then
         CURRENT_DN=$line
      elif [[ $line =~ ^vmwLKUPEndpointSslTrust: ]]; then
         echo "$CURRENT_DN" >> $STAGE_DIR/ls-service-reg-$SERVICE_ID.ldif
         echo "changetype: modify" >> $STAGE_DIR/ls-service-reg-$SERVICE_ID.ldif
         echo "replace: vmwLKUPEndpointSslTrust" >> $STAGE_DIR/ls-service-reg-$SERVICE_ID.ldif
         echo "vmwLKUPEndpointSslTrust:< file://$STAGE_DIR/trust-anchor-machine-ssl.hash" >> $STAGE_DIR/ls-service-reg-$SERVICE_ID.ldif
         echo "" >> $STAGE_DIR/ls-service-reg-$SERVICE_ID.ldif
      fi
   done
   
   if [ -f $STAGE_DIR/ls-service-reg-$SERVICE_ID.ldif ]; then
      echo "Updating service: $SERVICE_ID" | tee -a $LOG
      if ! $LDAP_MODIFY -v -h $VMDIR_FQDN -p 389 -D "$UPDATE_MACHINE_ACCOUNT_DN" -y $STAGE_DIR/.update-machine-account-password -f $STAGE_DIR/ls-service-reg-$SERVICE_ID.ldif >> $LOG 2>&1; then
         echo "Error updating service: please check logs for details"
      else
         ((++TOTAL_SERVICES_UPDATED))
      fi
   fi
}

#------------------------------
# Update the vpxd-extension certificate with EAM, Image Builder, and Auto Deploy
#------------------------------
function updateExtensionCerts() {
   UPDATE_EXT_THUMBPRINT_FAILED=0
   header "Updating VPXD Extension Certificate"
   
   task "Updating certificate with EAM"
   if /opt/vmware/bin/python /usr/lib/vmware-vpx/scripts/updateExtensionCertInVC.py -e com.vmware.vim.eam -s $HOSTNAME -c $VPXD_EXT_CERT -k $VPXD_EXT_KEY -u $VMDIR_USER_UPN -p $VMDIR_USER_PASSWORD 2>&1 | tee -a $LOG | grep -i 'successfully updated certificate' > /dev/null; then
      taskMessage "OK" "GREEN"
   else
      UPDATE_EXT_THUMBPRINT_FAILED=1
      taskMessage "ERROR" "YELLOW"
   fi

   task "Updating certificate with Auto Deploy"
   if /opt/vmware/bin/python /usr/lib/vmware-vpx/scripts/updateExtensionCertInVC.py -e com.vmware.rbd -s $HOSTNAME -c $VPXD_EXT_CERT -k $VPXD_EXT_KEY -u $VMDIR_USER_UPN -p $VMDIR_USER_PASSWORD 2>&1 | tee -a $LOG | grep -i 'successfully updated certificate' > /dev/null; then
      taskMessage "OK" "GREEN"
   else
      UPDATE_EXT_THUMBPRINT_FAILED=1
      taskMessage "ERROR" "YELLOW"
   fi
   
   IMAGE_BUILDER_EXT_FINGERPRINT=$($PSQL -d VCDB -U postgres -c "SELECT thumbprint FROM vpx_ext WHERE ext_id = 'com.vmware.imagebuilder'" -t | grep -v '^$' | tr -d ' ')
   
   if [ ! -z $IMAGE_BUILDER_EXT_FINGERPRINT ]; then
      task "Updating certificate with Image Builder"
      if /opt/vmware/bin/python /usr/lib/vmware-vpx/scripts/updateExtensionCertInVC.py -e com.vmware.imagebuilder -s $HOSTNAME -c $VPXD_EXT_CERT -k $VPXD_EXT_KEY -u $VMDIR_USER_UPN -p $VMDIR_USER_PASSWORD 2>&1 | tee -a $LOG | grep -i 'successfully updated certificate' > /dev/null; then
         taskMessage "OK" "GREEN"
      else
         UPDATE_EXT_THUMBPRINT_FAILED=1
         taskMessage "ERROR" "YELLOW"
      fi
   fi
   
   if [ $UPDATE_EXT_THUMBPRINT_FAILED -eq 1 ]; then
      updateVCExtensionThumbprints
   fi
}

#------------------------------
# Check the certificate thumbprints for default vCenter extensions
#------------------------------
function checkVCExtensionThumbprints() {
   header "Check vCenter Extension Thumbprints"         
   ANY_MISMATCHES=0
   VPXD_EXT_THUMB=$($VECS_CLI entry getcert --store vpxd-extension --alias vpxd-extension | openssl x509 -noout -fingerprint -sha1 | cut -d'=' -f2)
   MACHINE_SSL_THUMB=$($VECS_CLI entry getcert --store MACHINE_SSL_CERT --alias __MACHINE_CERT | openssl x509 -noout -fingerprint -sha1 | cut -d'=' -f2)
   AUTH_PROXY_THUMB=$(openssl x509 -noout -fingerprint -sha1 -in /var/lib/vmware/vmcam/ssl/vmcamcert.pem 2>/dev/null | cut -d'=' -f2)

   VPXD_EXT_EXTENSIONS=$($PSQL -d VCDB -U postgres -t -c "SELECT ext_id FROM vpx_ext WHERE thumbprint='$VPXD_EXT_THUMB'")
   MACHINE_SSL_EXTENSIONS=$($PSQL -d VCDB -U postgres -t -c "SELECT ext_id FROM vpx_ext WHERE thumbprint='$MACHINE_SSL_THUMB'")
   AUTH_PROXY_EXTENSION=$($PSQL -d VCDB -U postgres -t -c "SELECT ext_id FROM vpx_ext WHERE thumbprint='$AUTH_PROXY_THUMB'")
   
   IMAGE_BUILDER_EXT_FINGERPRINT=$($PSQL -d VCDB -U postgres -c "SELECT thumbprint FROM vpx_ext WHERE ext_id = 'com.vmware.imagebuilder'" -t | grep -v '^$' | tr -d ' ')

   task "ESX Agent Manager"
   if ! echo $VPXD_EXT_EXTENSIONS | grep 'com.vmware.vim.eam' > /dev/null 2>&1; then
      ANY_MISMATCHES=1
      mismatchMessage
   else
      statusMessage "MATCHES" "GREEN"
   fi

   task "Auto Deploy"
   if ! echo $VPXD_EXT_EXTENSIONS | grep 'com.vmware.rbd' > /dev/null 2>&1; then
      ANY_MISMATCHES=1
      mismatchMessage
   else
      statusMessage "MATCHES" "GREEN"
   fi
   
   if [ ! -z $IMAGE_BUILDER_EXT_FINGERPRINT ]; then
      task "Image Builder"
      if ! echo $VPXD_EXT_EXTENSIONS | grep 'com.vmware.imagebuilder' > /dev/null 2>&1; then
         ANY_MISMATCHES=1
         mismatchMessage
      else
         statusMessage "MATCHES" "GREEN"
      fi
   fi

   task "VMware Update Manager"
   if ! echo $VPXD_EXT_EXTENSIONS | grep 'com.vmware.vcIntegrity' > /dev/null 2>&1; then
      ANY_MISMATCHES=1
      mismatchMessage
   else
      statusMessage "MATCHES" "GREEN"
   fi

   task "vSAN Health"
   if ! echo $MACHINE_SSL_EXTENSIONS | grep 'com.vmware.vsan.health' > /dev/null 2>&1; then
      ANY_MISMATCHES=1
      mismatchMessage
   else
      statusMessage "MATCHES" "GREEN"
   fi

   task "Authentication Proxy"
   if ! echo $AUTH_PROXY_EXTENSION | grep 'com.vmware.vmcam' > /dev/null 2>&1; then
      ANY_MISMATCHES=1
      mismatchMessage
   else
      statusMessage "MATCHES" "GREEN"
   fi
   
   if [ "$ANY_MISMATCHES" == 1 ]; then
      echo $'\n'"${YELLOW}Mismatched thumbprints detected.${NORMAL}"
      read -p $'\n'"Update extension thumbprints? [n]: " UPDATE_THUMBPRINTS_INPUT
      
      if [ -z $UPDATE_THUMBPRINTS_INPUT ]; then
         UPDATE_THUMBPRINT="n"
      else
         UPDATE_THUMBPRINT=$UPDATE_THUMBPRINTS_INPUT
      fi
      
      if [[ "$UPDATE_THUMBPRINT" =~ ^[Yy] ]]; then echo ""; updateVCExtensionThumbprints; fi
   fi
}

#------------------------------
# Update the certificate thumbprints for default vCenter extensions
#------------------------------
function updateVCExtensionThumbprints() {
   header "Update vCenter Extension Thumbprints"
   VPXD_EXT_THUMB=$($VECS_CLI entry getcert --store vpxd-extension --alias vpxd-extension | openssl x509 -noout -fingerprint -sha1 2>/dev/null | cut -d'=' -f2)
   MACHINE_SSL_THUMB=$($VECS_CLI entry getcert --store MACHINE_SSL_CERT --alias __MACHINE_CERT | openssl x509 -noout -fingerprint -sha1 2>/dev/null | cut -d'=' -f2)
   AUTH_PROXY_THUMB=$(openssl x509 -noout -fingerprint -sha1 -in /var/lib/vmware/vmcam/ssl/vmcamcert.pem 2>/dev/null | cut -d'=' -f2)

   VPXD_EXT_EXTENSIONS=$($PSQL -d VCDB -U postgres -t -c "SELECT ext_id FROM vpx_ext WHERE thumbprint='$VPXD_EXT_THUMB'")
   MACHINE_SSL_EXTENSIONS=$($PSQL -d VCDB -U postgres -t -c "SELECT ext_id FROM vpx_ext WHERE thumbprint='$MACHINE_SSL_THUMB'")
   AUTH_PROXY_EXTENSION=$($PSQL -d VCDB -U postgres -t -c "SELECT ext_id FROM vpx_ext WHERE thumbprint='$AUTH_PROXY_THUMB'")
   IMG_BUILDER_EXTENSION=$($PSQL -d VCDB -U postgres -t -c "SELECT ext_id FROM vpx_ext WHERE ext_id='com.vmware.imagebuilder'")
   
   
   task "ESX Agent Manager"
   if ! echo $VPXD_EXT_EXTENSIONS | grep 'com.vmware.vim.eam' > /dev/null 2>&1; then
      $PSQL -d VCDB -U postgres -c "UPDATE vpx_ext SET thumbprint = '$VPXD_EXT_THUMB' WHERE ext_id = 'com.vmware.vim.eam'" >> $LOG 2>&1 || errorMessage "Unable to update extension thumbprint in VCDB"
      taskMessage "FIXED" "GREEN"
   else
      taskMessage "OK" "GREEN"
   fi

   task "Auto Deploy"
   if ! echo $VPXD_EXT_EXTENSIONS | grep 'com.vmware.rbd' > /dev/null 2>&1; then
      $PSQL -d VCDB -U postgres -c "UPDATE vpx_ext SET thumbprint = '$VPXD_EXT_THUMB' WHERE ext_id = 'com.vmware.rbd'" >> $LOG 2>&1 || errorMessage "Unable to update extension thumbprint in VCDB"
      taskMessage "FIXED" "GREEN"
   else
      taskMessage "OK" "GREEN"
   fi

   if [ ! -z $IMG_BUILDER_EXTENSION ]; then
      task "Image Builder"
      if ! echo $VPXD_EXT_EXTENSIONS | grep 'com.vmware.imagebuilder' > /dev/null 2>&1; then
         $PSQL -d VCDB -U postgres -c "UPDATE vpx_ext SET thumbprint = '$VPXD_EXT_THUMB' WHERE ext_id = 'com.vmware.imagebuilder'" >> $LOG 2>&1 || errorMessage "Unable to update extension thumbprint in VCDB"
         taskMessage "FIXED" "GREEN"
      else
         taskMessage "OK" "GREEN"
      fi         
   fi

   task "VMware Update Manager"
   if ! echo $VPXD_EXT_EXTENSIONS | grep 'com.vmware.vcIntegrity' > /dev/null 2>&1; then
      $PSQL -d VCDB -U postgres -c "UPDATE vpx_ext SET thumbprint = '$VPXD_EXT_THUMB' WHERE ext_id = 'com.vmware.vcIntegrity'" >> $LOG 2>&1 || errorMessage "Unable to update extension thumbprint in VCDB"
      taskMessage "FIXED" "GREEN"     
   else
      taskMessage "OK" "GREEN"
   fi

   task "vSAN Health"
   if ! echo $MACHINE_SSL_EXTENSIONS | grep 'com.vmware.vsan.health' > /dev/null 2>&1; then
      $PSQL -d VCDB -U postgres -c "UPDATE vpx_ext SET thumbprint = '$MACHINE_SSL_THUMB' WHERE ext_id = 'com.vmware.vsan.health'" >> $LOG 2>&1 || errorMessage "Unable to update extension thumbprint in VCDB"
      taskMessage "FIXED" "GREEN"
   else
      taskMessage "OK" "GREEN"
   fi

   task "Authentication Proxy"
   if ! echo $AUTH_PROXY_EXTENSION | grep 'com.vmware.vmcam' > /dev/null 2>&1; then
      $PSQL -d VCDB -U postgres -c "UPDATE vpx_ext SET thumbprint = '$AUTH_PROXY_THUMB' WHERE ext_id = 'com.vmware.vmcam'" >> $LOG 2>&1 || errorMessage "Unable to update extension thumbprint in VCDB"
      taskMessage "FIXED" "GREEN"
   else
      taskMessage "OK" "GREEN"
   fi
}

#------------------------------
# Verify a certificate, private key, and signing chain
#------------------------------
function verifyCertAndKey() {
   CHECK_CERT=$1
   CHECK_KEY=$2
   
   if [ ! -f $CHECK_CERT ]; then errorMessage "Could not locate certificate $CHECK_CERT"; fi
   if [ ! -f $CHECK_KEY ]; then errorMessage "Could not locate private key $CHECK_KEY"; fi

   CERT_HASH=$(openssl x509 -noout -modulus -in $CHECK_CERT 2>/dev/null | openssl md5)
   KEY_HASH=$(openssl rsa -noout -modulus -in $CHECK_KEY 2>/dev/null| openssl md5)
   
   echo "Modulus of $CHECK_CERT: $CERT_HASH" >> $LOG
   echo "Modulus of $CHECK_KEY: $KEY_HASH" >> $LOG
   if [ "$CERT_HASH" != "$KEY_HASH" ]; then errorMessage "The private key $CHECK_KEY does not correspond to the certificate $CHECK_CERT"; fi
}

#------------------------------
# Verifies root chain by subject/issuer strings
#------------------------------
function verifyRootChain() {
   csplit -z -f $STAGE_DIR/root-chain-cert- -b %02d.crt $2 "/-----BEGIN CERTIFICATE-----/" "{*}" 2>&1 >> $LOG
   
   echo "Contents of trusted root chain $2" >> $LOG
   openssl crl2pkcs7 -nocrl -certfile $2 | openssl pkcs7 -print_certs -noout >> $LOG
   
   ISSUER_TO_CHECK=$(openssl x509 -noout -issuer -in $1 | sed -e 's/issuer= //')
   for cert in $(ls $STAGE_DIR/root-chain-cert-*); do
      CURRENT_SUBJECT=$(openssl x509 -noout -subject -in $cert | sed -e 's/subject= //')
      if [ "$ISSUER_TO_CHECK" != "$CURRENT_SUBJECT" ]; then return 1; fi
      ISSUER_TO_CHECK=$(openssl x509 -noout -issuer -in $cert | sed -e 's/issuer= //')
   done
   if [ "$ISSUER_TO_CHECK" != "$CURRENT_SUBJECT" ]; then
      return 1
   else
      return 0   
   fi
}

#------------------------------
# Check if SSL Interception is in play
#------------------------------
function checkSSLInterception() {
   header "Checking for SSL Interception"
   task "Checkig hostupdate.vmware.com"
   HOSTUPDATE_ISSUER=$(echo | openssl s_client -connect hostupdate.vmware.com:443 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null | awk -F'/' '{for(i=1; i<=NF;i++) if($i ~ /^CN/) {print $i}}' | tr -d 'CN=')
   
   if [ ! -z "$HOSTUPDATE_ISSUER" ]; then
      taskMessage "OK" "GREEN"
      if [ "$HOSTUPDATE_ISSUER" != "$HOSTUPDATE_ISSUER_EXPECTED" ]; then
         echo $'\n'"Issuing CA for hostupdate.vmware.com is ${YELLOW}${HOSTUPDATE_ISSUER}${NORMAL}" | tee -a $LOG
         echo "The expected issuer is ${GREEN}${HOSTUPDATE_ISSUER_EXPECTED}${NORMAL}" | tee -a $LOG
         echo $'\n'"${YELLOW}SSL Interception is likely taking place.${NORMAL}" | tee -a $LOG
         
         read -p $'\n'"Download and install the CA certificates from the proxy? [n]: " DOWNLOAD_PROXY_CA_CERTS_INPUT
         
         if [ -z "$DOWNLOAD_PROXY_CA_CERTS_INPUT" ]; then
            DOWNLOAD_PROXY_CA_CERTS="n"
         else
            DOWNLOAD_PROXY_CA_CERTS=$DOWNLOAD_PROXY_CA_CERTS_INPUT
         fi
         
         if [[ $DOWNLOAD_PROXY_CA_CERTS =~ ^[Yy] ]]; then
            echo "User has choosen to download proxy CA certs" >> $LOG
            downloadProxyCACerts
         else
            echo "User has choosen not to download proxy CA certs" >> $LOG
         fi
      else
         echo $'\n'"Issuing CA for hostupdate.vmware.com is ${GREEN}${HOSTUPDATE_ISSUER}${NORMAL}"$'\n'
      fi
   else
      taskMessae "ERROR" "YELLOW"
      echo $'\n'"${YELLOW}Could not identify the issuer of the certificate for hostupdate.vmware.com"
      echo "Check your network connection and try again.${NORMAL}"$'\n'
   fi
}

#------------------------------
# Download CA certs from proxy used for SSL Interception
#------------------------------
function downloadProxyCACerts() {
   echo ""
   
   if [ -z $VMDIR_USER_UPN ]; then
      getSSOCredentials

      verifySSOCredentials
   fi
   
   echo ""
   task "Downloadng certificate chain from the proxy"
   echo | openssl s_client -connect hostupdate.vmware.com:443 2>/dev/null -showcerts | sed -n '/^-----BEGIN CERTIFICATE-----/,/^-----END CERTIFICATE-----/p' | csplit -z -f $STAGE_DIR/proxy-cert- -b%02d.crt /dev/stdin "/-----BEGIN CERTIFICATE-----/" "{*}" >> $LOG
   if [ "$(ls -l $STAGE_DIR/proxy-cert* 2>/dev/null)" != "" ]; then
      taskMessage "OK" "GREEN"
      /usr/bin/rm $STAGE_DIR/proxy-cert-00.crt
      for cert in $(ls $STAGE_DIR/proxy-cert-* 2>/dev/null); do cat $cert >> $STAGE_DIR/proxy-ca-chain.pem; done
      if [ -f $STAGE_DIR/proxy-ca-chain.pem ]; then
         task "Publishing certificates to VMware Directory"
         $DIR_CLI trustedcert publish --chain --cert $STAGE_DIR/proxy-ca-chain.pem --login $VMDIR_USER --password "$(cat $STAGE_DIR/.vmdir-user-password)" 2>&1 >> $LOG || errorMessage "Unable to publish proxy CA certificates to VMware Directory."
         taskMessage "OK" "GREEN"
         task "Refreshing CA certificates to VECS"
         $VECS_CLI force-refresh || errorMessage "Unable to refresh CA certificates in VECS"
         taskMessage "OK" "GREEN"
         
         if [[ "$VC_VERSION" =~ ^7 ]] && [[ $VC_BUILD -ge 17327517 ]]; then
            task "Adding certificates to python CA store"
            cat $STAGE_DIR/proxy-ca-chain.pem >> /usr/lib/python3.7/site-packages/certifi/cacert.pem
            taskMessage "OK" "GREEN"
            PUBLISH_INSTRUCTIONS=$'\n'"and /usr/lib/python3.7/site-packages/certifi/cacert.pem"
         else
            PUBLISH_INSTRUCTIONS=""
         fi
         
         NUM_PROXY_CA_CERTS=$(ls -l $STAGE_DIR/proxy-cert-* | wc -l)
         CERT_FILE_INDEX=$(printf "%02d" $((NUM_PROXY_CA_CERTS-1)))
         LAST_PROXY_CA_SUBJECT=$(openssl x509 -noout -subject -in $STAGE_DIR/proxy-cert-$CERT_FILE_INDEX.crt 2>/dev/null | sed -e 's/subject= //')
         LAST_PROXY_CA_ISSUER=$(openssl x509 -noout -issuer -in $STAGE_DIR/proxy-cert-$CERT_FILE_INDEX.crt 2>/dev/null | sed -e 's/issuer= //')
            
         if [ "$LAST_PROXY_CA_SUBJECT" != "$LAST_PROXY_CA_ISSUER" ]; then
            echo $'\n'"${YELLOW}There proxy does not provide the Root CA certificate in the chain."
            echo "Please aquire this certificate and publish it to VMware Directory $PUBLISH_INSTRUCTIONS manually.${NORMAL}"
         fi
      else
         echo $'\n'"${YELLOW}There proxy does not appear to provide any of the CA certificates."
         echo "Please aquire these certificates and publish them to VMware Directory $PUBLISH_INSTRUCTIONS manually.${NORMAL}"
      fi      
   fi
}

#------------------------------
# Check configuration of the STS server
#------------------------------
function checkSTSCertConfig() {
   header "Checking STS server configuration"
   task "Checking VECS store configuration"
   STS_CONNECTOR_STORE=$(grep 'store=' /usr/lib/vmware-sso/vmware-sts/conf/server.xml | awk '{for(i=1;i<=NF;i++) if($i ~ /^store/) {print $i}}' | tr -d '>' | awk -F'=' '{print $NF}' | tr -d '"')
   STS_CERTIFICATE_STORE=$(grep 'certificateKeystoreFile=' /usr/lib/vmware-sso/vmware-sts/conf/server.xml | awk '{for(i=1;i<=NF;i++) if($i ~ /^certificateKeystoreFile/) {print $i}}' | tr -d '>' | awk -F'=' '{print $NF}' | tr -d '"')
   taskMessage "OK" "GREEN"
   
   if [ "$STS_CONNECTOR_STORE" == "MACHINE_SSL_CERT" ] && [ "$STS_CERTIFICATE_STORE" == "MACHINE_SSL_CERT" ]; then
      echo $'\n'"The STS server is using the ${GREEN}MACHINE_SSL_CERT${NORMAL} VECS store."
   else
      if [ "$STS_CONNECTOR_STORE" == "$STS_CERTIFICATE_STORE" ]; then
         echo $'\n'"The STS server is using the ${YELLOW}${STS_CONNECTOR_STORE}${NORMAL} VECS store."
      else
         echo $'\n'"The STS server is using the following VECS stores:"
         echo "Server > Service > Connector: ${YELLOW}${STS_CONNECTOR_STORE}${NORMAL}"
         echo "Server > Service > SSLHostConfig > Certificate: ${YELLOW}${STS_CERTIFICATE_STORE}${NORMAL}"
      fi
     
      read -p $'\n'"Update STS server configuration to use the ${GREEN}MACHINE_SSL_CERT${NORMAL} store? [n]: " UPDATE_STS_CONFIG_PROMPT
     
      if [ -z $UPDATE_STS_CONFIG_PROMPT ]; then
         UPDATE_STS_CONFIG="n"
      else
         UPDATE_STS_CONFIG=$UPDATE_STS_CONFIG_PROMPT
      fi
     
      if [[ $UPDATE_STS_CONFIG =~ ^[Yy] ]]; then
         header "Updating STS server configuration"
         task "Backing up configuration"
         cp /usr/lib/vmware-sso/vmware-sts/conf/server.xml /usr/lib/vmware-sso/vmware-sts/conf/server.xml.backup 2>>$LOG || errorMessage "Unable to backup /usr/lib/vmware-sso/vmware-sts/conf/server.xml"
         taskMessage "OK" "GREEN"
         
         task "Changing STS server configuration"
         sed -i 's/STS_INTERNAL_SSL_CERT/MACHINE_SSL_CERT/g' /usr/lib/vmware-sso/vmware-sts/conf/server.xml || errorMessage "Unable to update STS server configuration"
         taskMessage "OK" "GREEN"
        
         task "Stopping STS service"
         service-control --stop vmware-stsd 2>&1 >> $LOG || errorMessage "Unable to stop the STS service."
         taskMessage "OK" "GREEN"
        
         task "Starting STS service"
         service-control --start vmware-stsd 2>&1 >> $LOG || errorMessage "Unable to start the STS service."
         taskMessage "OK" "GREEN"
      fi
   fi
}

#------------------------------
# Check configuration of Smart Card authentication
#------------------------------
function checkSmartCardConfiguration() {
   header "Smart Card Authentication Configuration"
   
   echo " 1. View Reverse Proxy configuration" | tee -a $LOG
   echo " 2. View CA certificates for Smart Card authentication" | tee -a $LOG
   echo " 3. View Smart Card authentication options" | tee -a $LOG
   echo ""
   read -p "Select an option [1]: " SMART_CARD_INPUT
   
   if [ -z $SMART_CARD_INPUT ]; then
      SMART_CARD_OPTION=1
   else
      SMART_CARD_OPTION=$SMART_CARD_INPUT
   fi
   
   case $SMART_CARD_OPTION in
      1)
         checkSmartCardReverseProxy
         ;;
      2)
         checkSmartCardCACerts
         ;;
      3)
         checkSmartCardOptions
         ;;
   esac
}

#------------------------------
# Check Reverse Proxy Smart Card configuration
#------------------------------
function checkSmartCardReverseProxy() {
  header "Smart Card Reverse Proxy Configuration"
  
  task "Request client certificate"
  if grep ClientCertificate /etc/vmware-rhttpproxy/config.xml > /dev/null; then
     if grep ClientCertificate /etc/vmware-rhttpproxy/config.xml | grep '<!--' > /dev/null; then
        statusMessage "WARNING" "YELLOW"
        echo $'\n'"${YELLOW}The reverse proxy is configured to request a client certificate,"
        echo "but the configuration parameter is commented out."
        echo "Remove the HTML comment tags (<!--, -->) from the line and restart the reverse proxy service.${NORMAL}"
     else
        statusMessage "CONFIGURED" "GREEN"
     fi
  else
     statusMessage "NOT CONFIGURED" "YELLOW"
  fi
  
  task "Check exclusive CA list file"
  
  if grep clientCAListFile /etc/vmware-rhttpproxy/config.xml > /dev/null; then
     if grep clientCAListFile /etc/vmware-rhttpproxy/config.xml | grep '<!--' > /dev/null; then
        statusMessage "WARNING" "YELLOW"
        echo $'\n'"${YELLOW}The reverse proxy is configured to filter client certificates based on the issuing CA,"
        echo "but the configuration parameter is commented out."
        echo "Remove the HTML comment tags (<!--, -->) from the line and restart the reverse proxy service.${NORMAL}"
     else
        CLIENT_CA_LIST_FILE=$(grep CAListFile /etc/vmware-rhttpproxy/config.xml | sed 's/.*>\(.*\)<.*/\1/')
        if ! grep CAListFile /etc/vmware-rhttpproxy/config.xml | sed 's/.*>\(.*\)<.*/\1/' | grep '^/' > /dev/null; then
           CLIENT_CA_LIST_FILE="/etc/vmware-rhttpproxy/$CLIENT_CA_LIST_FILE"
        fi
        
        if grep 'BEGIN CERTIFICATE' $CLIENT_CA_LIST_FILE > /dev/null; then
           statusMessage "CONFIGURED" "GREEN"
           
           header "Exclusive Smart Card Issuing CAs"
           csplit -z -f $STAGE_DIR/sc-ca-cert- -b %02d.crt $CLIENT_CA_LIST_FILE "/-----BEGIN CERTIFICATE-----/" "{*}" > /dev/null
           
           i=1
           for cert in $(ls $STAGE_DIR/sc-ca-cert-*); do
              SC_CA_SUBJECT=$(openssl x509 -text -noout -in $cert | grep 'Subject:' | sed -e 's/^[[:space:]]*//')
              SC_CA_NOT_AFTER=$(openssl x509 -text -noout -in $cert | grep 'Not After' | sed -e 's/^[[:space:]]*//')
              printf "%2s. ${NORMAL}%s\n" $i "$SC_CA_SUBJECT"
              if openssl x509 -noout -in $cert -checkend 0 2>/dev/null; then
                 echo $'\t'"$SC_CA_NOT_AFTER"$'\n'
              else
                 echo $'\t'"$SC_CA_NOT_AFTER"$'\n' | sed -e "s/Not Before/${RED}&/"
              fi
              ((++i)) 
           done
        else
           statusMessage "WARNING" "YELLOW"
           echo $'\n'"${YELLOW}The reverse proxy is configured to filter client certificates based on the issuing CA,"
           echo "but the file does not contain any Base-64 certificate hashes."
        fi
     fi
  else
     statusMessage "NOT CONFIGURED" "YELLOW"
  fi
}

#------------------------------
# Check Smart Card issuing CA certs
#------------------------------
function checkSmartCardCACerts() {
   getSSOCredentials
   verifySSOCredentials
   echo ""
   header "Smart Card CA certs (VMware Directory)"   
   
   CAC_CAS=$($LDAP_SEARCH -LLL -h $VMDIR_FQDN -b "cn=DefaultClientCertCAStore,cn=ClientCertAuthnTrustedCAs,cn=Default,cn=ClientCertificatePolicies,cn=$SSO_DOMAIN,cn=Tenants,cn=IdentityManager,cn=Services,$VMDIR_DOMAIN_DN" -D "cn=$VMDIR_USER,cn=users,$VMDIR_DOMAIN_DN" -y $STAGE_DIR/.vmdir-user-password "(objectclass=vmwSTSTenantTrustedCertificateChain)" userCertificate 2>/dev/null | tr -d '\n' | tr -d ' '| sed -e 's/dn:/\n&/g' -e 's/userCertificate::/\n&/g' | grep '^userCertificate' | sed 's/userCertificate:://g')
   
   if [ -n "$CAC_CAS" ]; then
      i=1
      for hash in $CAC_CAS; do
         TEMP_CERT="-----BEGIN CERTIFICATE-----"$'\n'
         TEMP_CERT+=$(echo "$hash" | fold -c64)
         TEMP_CERT+=$'\n'"-----END CERTIFICATE-----" 
         SC_CA_SUBJECT=$(echo "$TEMP_CERT" | openssl x509 -text -noout | grep 'Subject:' | sed -e 's/^[[:space:]]*//')
         SC_CA_NOT_AFTER=$(echo "$TEMP_CERT" | openssl x509 -text -noout | grep 'Not After' | sed -e 's/^[[:space:]]*//')
         printf "%2s. ${NORMAL}%s\n" $i "$SC_CA_SUBJECT"
         if echo "$TEMP_CERT" | openssl x509 -noout -checkend 0 2>/dev/null; then
            echo $'\t'"$SC_CA_NOT_AFTER"$'\n'
         else
            echo $'\t'"$SC_CA_NOT_AFTER"$'\n' | sed -e "s/Not Before/${RED}&/"
         fi         
         ((++i))
      done
   else
      echo "${YELLOW}No Smart Card issuing CA certificates found in VMware Directory.${NORMAL}"
   fi
}

#------------------------------
# Check Smart Card configuration options
#------------------------------
function checkSmartCardOptions() {
   header "Smart Card SSO options"
   echo -n "Gathering authn SSO options..."
   SC_SSO_CONFIG=$(sso-config.sh -get_authn_policy -t $SSO_DOMAIN 2>/dev/null)
   echo -ne "\r"
   SC_SSO_USE_CRL=$(echo "$SC_SSO_CONFIG" | grep useCertCRL | awk '{print $NF}')
   SC_SSO_CRL_URL=$(echo "$SC_SSO_CONFIG" | grep CRLUrl | awk '{print $NF}')
   SC_SSO_CRL_FAILOVER=$(echo "$SC_SSO_CONFIG" | grep useCRLAsFailOver | awk '{print $NF}')
   SC_SSO_USE_OCSP=$(echo "$SC_SSO_CONFIG" | grep useOCSP | awk '{print $NF}')
   
   task "Use CRL in certificate"
   if [ "$SC_SSO_USE_CRL" == "false" ]; then
      statusMessage "FALSE" "YELLOW"
   else
      statusMessage "TRUE" "GREEN"
   fi
   
   task "CRL override URL"
   if [ "$SC_SSO_CRL_URL" == "UndefinedConfig" ]; then
      statusMessage "NONE" "YELLOW"
   else
      statusMessage "$SC_SSO_CRL_URL" "GREEN"
   fi
   
   task "Use CRL as failover"
   if [ "$SC_SSO_CRL_FAILOVER" == "false" ]; then
      statusMessage "FALSE" "YELLOW"
   else
      statusMessage "TRUE" "GREEN"
   fi
   
   task "Use OCSP"
   if [ "$SC_SSO_USE_OCSP" == "false" ]; then
      statusMessage "FALSE" "YELLOW"
   else
      statusMessage "TRUE" "GREEN"
   fi
}

# commands
VECS_CLI="/usr/lib/vmware-vmafd/bin/vecs-cli"
DIR_CLI="/usr/lib/vmware-vmafd/bin/dir-cli"
VMAFD_CLI="/usr/lib/vmware-vmafd/bin/vmafd-cli"
CERTOOL="/usr/lib/vmware-vmca/bin/certool"
LDAP_DELETE="/opt/likewise/bin/ldapdelete"
LDAP_SEARCH="/opt/likewise/bin/ldapsearch"
LDAP_MODIFY="/opt/likewise/bin/ldapmodify"
PSQL="/opt/vmware/vpostgres/current/bin/psql"

# variables
VC_VERSION=$(grep 'CLOUDVM_VERSION:' /etc/vmware/.buildInfo | awk -F':' '{print $NF}' | awk -F'.' '{print $1"."$2}')
VC_BUILD=$(vpxd -v | awk -F'-' '{print $NF}')
LOG="vCert.log"
CLEANUP=1
TEMP_DIR="/tmp/vCert-$(date +%Y%m%d)"
STAGE_DIR="$TEMP_DIR/stage"
REQUEST_DIR="$TEMP_DIR/requests"
BACKUP_DIR="$TEMP_DIR/backup"
REPORT="$TEMP_DIR/certificate-report.txt"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
NODE_TYPE=$(cat /etc/vmware/deployment.node.type)
HOSTNAME=$(hostname -f)
HOSTNAME_LC=$(echo $HOSTNAME | awk '{print tolower($0)}')
HOSTNAME_SHORT=$(hostname -s)
IP=$(ip a | grep -A 2 eth0 | grep inet | awk '{print $2}' | awk -F'/' '{print $1}')
PNID=$($VMAFD_CLI get-pnid --server-name localhost)
PNID_LC=$(echo $PNID | awk '{print tolower($0)}')
MACHINE_ID=$($VMAFD_CLI get-machine-id --server-name localhost)
SSO_DOMAIN=$($VMAFD_CLI get-domain-name --server-name localhost)
SSO_SITE=$($VMAFD_CLI get-site-name --server-name localhost)
VMDIR_FQDN=$($VMAFD_CLI get-ls-location --server-name localhost | sed -e 's/:443//g' | awk -F'/' '{print $3}')
VMDIR_DOMAIN_DN="dc=$(echo $SSO_DOMAIN | sed 's/\./,dc=/g')"
VMDIR_MACHINE_PASSWORD=$(/opt/likewise/bin/lwregshell list_values '[HKEY_THIS_MACHINE\services\vmdir]' | grep dcAccountPassword | awk -F"  " '{print $NF}' | awk '{print substr($0,2,length($0)-2)}' | sed -e 's/\\"/"/g' -e 's/\\\\/\\/g')
VMDIR_MACHINE_ACCOUNT_DN=$(/opt/likewise/bin/lwregshell list_values '[HKEY_THIS_MACHINE\services\vmdir]' | grep '"dcAccountDN"' | awk -F"  " '{print $NF}' | awk '{print substr($0,2,length($0)-2)}')
VMDIR_USER_UPN_DEFAULT="administrator@$SSO_DOMAIN"
VMDIR_USER=""
VMDIR_USER_UPN=""
VMDIR_USER_PASSWORD=""
if [ $NODE_TYPE != "management" ]; then
   PSC_DEFAULT="localhost"
else
   PSC_DEFAULT=$VMDIR_FQDN
fi
HOSTUPDATE_ISSUER_EXPECTED="Digiert SHA2 Secure Server A"
PSC_LOCATION=""
CERT_HASHES=()
TRUSTED_ROOT_CHAIN=""
VMCA_REPLACE="SELF-SIGNED"
MACHINE_SSL_REPLACE="VMCA-SIGNED"
SOLUTION_USER_REPLACE="VMCA-SIGNED"
VMDIR_REPLACE="VMCA-SIGNED"
AUTH_PROXY_REPLACE="VMCA-SIGNED"
AUTO_DEPLOY_CA_REPLACE="SELF-SIGNED"

# CSR defaults and variables
VMCA_CN_DEFAULT="CA"
CSR_COUNTRY_DEFAULT="US"
CSR_ORG_DEFAULT="VMware"
CSR_ORG_UNIT_DEFAULT="VMware"
CSR_STATE_DEFAULT="California"
CSR_LOCALITY_DEFAULT="Palo Alto"
CSR_COUNTRY=""
CSR_ORG=""
CSR_ORG_UNIT=""
CSR_STATE=""
CSR_LOCALITY=""
CSR_IP=""
CSR_EMAIL=""
CSR_ADDITIONAL_DNS=""


# script workflow

preStartOperations

operationMenu

processOperationMenu
