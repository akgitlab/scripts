# A faster way to set all the internal and external URLs is with the Set-ExchangeURLs.ps1 PowerShell script.
# Save the script on the Exchange Server C:\Scripts folder. If you don’t have a scripts folder, create one.

# Ensure that the file is unblocked to prevent any errors when running the script.
# Read more in the article Not digitally signed error when running PowerShell script.

# © Andrey Kuznetsov, 2023.04.14
# Telegram: https://t.me/akmsg

# Change wariables in line 1, 2, 3

$servername = "ex01"
$internal = "mail.example.com"
$external = "ex01.example.local"

# Configure URL for Outlook Autodiscover
Get-ClientAccessService -Identity $servername | Set-ClientAccessService -AutoDiscoverServiceInternalUri "https://$internal/Autodiscover/Autodiscover.xml" -AutoDiscoverServiceExternalUri "https://$external/Autodiscover/Autodiscover.xml"

# Configure URL for ActiveSync
Get-ActiveSyncVirtualDirectory -Server $servername | Set-ActiveSyncVirtualDirectory -ExternalUrl "https://$external/Microsoft-Server-ActiveSync" -InternalUrl "https://$internal/Microsoft-Server-ActiveSync"

# Configure URL for MAPI
Get-MapiVirtualDirectory -Server $servername | Set-MapiVirtualDirectory -ExternalUrl "https://$external/mapi" -InternalUrl "https://$internal/mapi"

# Configure URL for Exchange Control Panel
Get-EcpVirtualDirectory -Server $servername | Set-EcpVirtualDirectory -ExternalUrl "https://$external/ecp" -InternalUrl "https://$internal/ecp"

# Configure URL for Outlook Web Access
Get-OwaVirtualDirectory -Server $servername | Set-OwaVirtualDirectory -ExternalUrl "https://$external/owa" -InternalUrl "https://$internal/owa"

# Configure URL for Offline Address Book
Get-OabVirtualDirectory -Server $servername | Set-OabVirtualDirectory -ExternalUrl "https://$external/OAB" -InternalUrl "https://$internal/OAB"

# Configure URL for PowerShell
Get-PowerShellVirtualDirectory -Server $servername | Set-PowerShellVirtualDirectory -ExternalUrl "https://$external/powershell" -InternalUrl "https://$internal/powershell"

# Configure URL for Exchange Web Services
Get-WebServicesVirtualDirectory -Server $servername | Set-WebServicesVirtualDirectory -ExternalUrl "https://$external/EWS/Exchange.asmx" -InternalUrl "https://$internal/EWS/Exchange.asmx"

# Configure URL for Outlook Anywhere
Get-OutlookAnywhere -Server $servername | Set-OutlookAnywhere -ExternalHostname "$external" -InternalHostname "$internal" -ExternalClientsRequireSsl $true -InternalClientsRequireSsl $true -DefaultAuthenticationMethod NTLM -Confirm:$false

# Restart IIS service
iisreset
