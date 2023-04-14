# A faster way to set all the external URLs is with the Set-ExchangeURLs.ps1 PowerShell script.
# Save the script on the Exchange Server C:\Scripts folder. If you don’t have a scripts folder, create one.

# Ensure that the file is unblocked to prevent any errors when running the script.
# Read more in the article Not digitally signed error when running PowerShell script.

# © Andrey Kuznetsov, 2023.04.14
# Telegram: https://t.me/akmsg

# Change wariables
$external = "mail.example.com"

# Configure URL for Outlook Autodiscover
Get-ClientAccessService -Identity $env:computername | Set-ClientAccessService -AutoDiscoverServiceExternalUri "https://$external/Autodiscover/Autodiscover.xml"

# Configure URL for ActiveSync
Get-ActiveSyncVirtualDirectory -Server $env:computername | Set-ActiveSyncVirtualDirectory -ExternalUrl "https://$external/Microsoft-Server-ActiveSync"

# Configure URL for MAPI
Get-MapiVirtualDirectory -Server $env:computername | Set-MapiVirtualDirectory -ExternalUrl "https://$external/mapi"

# Configure URL for Exchange Control Panel
Get-EcpVirtualDirectory -Server $env:computername | Set-EcpVirtualDirectory -ExternalUrl "https://$external/ecp"

# Configure URL for Outlook Web Access
Get-OwaVirtualDirectory -Server $env:computername | Set-OwaVirtualDirectory -ExternalUrl "https://$external/owa"

# Configure URL for Offline Address Book
Get-OabVirtualDirectory -Server $env:computername | Set-OabVirtualDirectory -ExternalUrl "https://$external/OAB"

# Configure URL for PowerShell
Get-PowerShellVirtualDirectory -Server $env:computername | Set-PowerShellVirtualDirectory -ExternalUrl "https://$external/powershell"

# Configure URL for Exchange Web Services
Get-WebServicesVirtualDirectory -Server $env:computername | Set-WebServicesVirtualDirectory -ExternalUrl "https://$external/EWS/Exchange.asmx"

# Configure URL for Outlook Anywhere
Get-OutlookAnywhere -Server $env:computername | Set-OutlookAnywhere -ExternalHostname "$external" -ExternalClientsRequireSsl $true -ExternalClientAuthenticationMethod NTLM -Confirm:$false

# Restart IIS service
iisreset
