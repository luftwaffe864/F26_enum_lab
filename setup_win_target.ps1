#Requires -RunAsAdministrator
<#
.SYNOPSIS
  ENUM QUEST — provision Windows Server 2019 target

.DESCRIPTION
  Plants local users, SMB shares, IIS site (with hidden paths), DNS zone,
  and firewall rules for the DCIG enumeration lab.

.EXAMPLE
  .\setup_win_target.ps1
  .\setup_win_target.ps1 -UbuntuIp 192.168.1.10 -WinIp 192.168.1.11
#>
param(
  [string]$LabDomain = $(if ($env:LAB_DOMAIN) { $env:LAB_DOMAIN } else { "vault.lab" }),
  [string]$UbuntuHost = $(if ($env:TARGET_UBUNTU_HOST) { $env:TARGET_UBUNTU_HOST } else { "vault-web" }),
  [string]$WinHost = $(if ($env:TARGET_WIN_HOST) { $env:TARGET_WIN_HOST } else { "vault-dc" }),
  [string]$UbuntuIp = $(if ($env:TARGET_UBUNTU_IP) { $env:TARGET_UBUNTU_IP } else { "192.168.1.10" }),
  [string]$WinIp = $(if ($env:TARGET_WIN_IP) { $env:TARGET_WIN_IP } else { "192.168.1.11" })
)

$ErrorActionPreference = "Stop"
function Log($m) { Write-Host "[win-target] $m" }
Log "Ubuntu $UbuntuIp / Windows $WinIp"

# --- Features ---
Log "ensuring IIS, DNS, File Services"
$features = @(
  "Web-Server",
  "Web-Common-Http",
  "Web-Default-Doc",
  "Web-Dir-Browsing",
  "Web-Http-Errors",
  "Web-Static-Content",
  "DNS",
  "FS-FileServer"
)
foreach ($f in $features) {
  $state = Get-WindowsFeature -Name $f -ErrorAction SilentlyContinue
  if ($state -and -not $state.Installed) {
    Install-WindowsFeature -Name $f -IncludeManagementTools | Out-Null
  }
}

# --- Local users ---
# Domain password policy rejects passwords that contain the username (or a
# 3+ char piece of it). Keep these unrelated to svc_backup / intern.
Log "planting local users svc_backup, intern"
function Ensure-LocalUser($Name, $Password, $Description) {
  $secure = ConvertTo-SecureString $Password -AsPlainText -Force
  if (Get-LocalUser -Name $Name -ErrorAction SilentlyContinue) {
    Set-LocalUser -Name $Name -Password $secure -Description $Description
  } else {
    New-LocalUser -Name $Name -Password $secure -FullName $Name -Description $Description -PasswordNeverExpires | Out-Null
  }
}
# 20+ chars, upper/lower/digit/symbol, no overlap with account names
Ensure-LocalUser "svc_backup" 'X9#mK2$pL7!qR4@wN8z' "Backup service account"
Ensure-LocalUser "intern" 'Y8@nJ3#vQ6!tH5$uM2x' "Temporary intern"

# --- SMB shares ---
Log "planting SMB shares Public, Finance, IT$"
$public = "C:\Shares\Public"
$finance = "C:\Shares\Finance"
$it = "C:\Shares\IT"
New-Item -ItemType Directory -Force -Path $public, $finance, $it | Out-Null
Set-Content -Path "$public\welcome.txt" -Value "Welcome to the Public share.`r`nFLAG{smb_public_read}`r`n"
Set-Content -Path "$finance\ledger.txt" -Value "confidential finance data - access denied to guests"
Set-Content -Path "$it\inventory.txt" -Value "IT$ hidden share inventory"

function Ensure-Share($Name, $Path, $Description, [switch]$Hidden) {
  $shareName = if ($Hidden) { "$Name`$" } else { $Name }
  if (Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue) {
    Remove-SmbShare -Name $shareName -Force
  }
  New-SmbShare -Name $shareName -Path $Path -Description $Description -FullAccess "Everyone" | Out-Null
}

Ensure-Share -Name "Public" -Path $public -Description "Public read share"
Ensure-Share -Name "Finance" -Path $finance -Description "Finance (restricted)"
# Restrict Finance: remove Everyone read via ACL (share still lists)
icacls $finance /inheritance:r | Out-Null
icacls $finance /grant:r "Administrators:(OI)(CI)F" | Out-Null
icacls $finance /grant:r "SYSTEM:(OI)(CI)F" | Out-Null

if (Get-SmbShare -Name "IT$" -ErrorAction SilentlyContinue) {
  Remove-SmbShare -Name "IT$" -Force
}
New-SmbShare -Name "IT$" -Path $it -Description "Hidden IT share" -FullAccess "Administrators" | Out-Null

# Guest access for Public (classroom enum)
try {
  Grant-SmbShareAccess -Name "Public" -AccountName "Everyone" -AccessRight Read -Force | Out-Null
} catch {}

# --- IIS ---
Log "planting IIS site"
Import-Module WebAdministration -ErrorAction SilentlyContinue
$www = "C:\inetpub\wwwroot"
New-Item -ItemType Directory -Force -Path "$www\secret", "$www\assets" | Out-Null

@"
<!DOCTYPE html>
<html><head><title>Vault DC</title></head>
<body style="font-family:sans-serif;margin:2rem">
  <h1>Vault Corp — Windows Portal</h1>
  <p>Host: $WinHost · Domain: $LabDomain</p>
  <p>See <a href="/robots.txt">robots.txt</a>.</p>
</body></html>
"@ | Set-Content -Path "$www\index.html" -Encoding UTF8

@"
User-agent: *
Disallow: /secret
"@ | Set-Content -Path "$www\robots.txt" -Encoding UTF8

@"
<!DOCTYPE html>
<html><head><title>Secret</title></head>
<body>
  <h1>Secret stash</h1>
  <p><code>FLAG{iis_secret_stash}</code></p>
</body></html>
"@ | Set-Content -Path "$www\secret\index.html" -Encoding UTF8

if (Get-Website -Name "Default Web Site" -ErrorAction SilentlyContinue) {
  Start-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
}

# --- DNS ---
Log "planting DNS zone $LabDomain"
Import-Module DNSServer -ErrorAction SilentlyContinue
if (-not (Get-DnsServerZone -Name $LabDomain -ErrorAction SilentlyContinue)) {
  Add-DnsServerPrimaryZone -Name $LabDomain -ZoneFile "$LabDomain.dns" -DynamicUpdate None
}
# Clear and re-add records idempotently
Get-DnsServerResourceRecord -ZoneName $LabDomain -ErrorAction SilentlyContinue |
  Where-Object { $_.HostName -notin "@", "DomainDnsZones", "ForestDnsZones" } |
  ForEach-Object {
    try { Remove-DnsServerResourceRecord -ZoneName $LabDomain -InputObject $_ -Force -ErrorAction SilentlyContinue } catch {}
  }

Add-DnsServerResourceRecordA -ZoneName $LabDomain -Name $UbuntuHost -IPv4Address $UbuntuIp -CreatePtr:$false -ErrorAction SilentlyContinue
Add-DnsServerResourceRecordA -ZoneName $LabDomain -Name $WinHost -IPv4Address $WinIp -CreatePtr:$false -ErrorAction SilentlyContinue
Add-DnsServerResourceRecordA -ZoneName $LabDomain -Name "ns1" -IPv4Address $UbuntuIp -CreatePtr:$false -ErrorAction SilentlyContinue
Add-DnsServerResourceRecordA -ZoneName $LabDomain -Name "mail" -IPv4Address $UbuntuIp -CreatePtr:$false -ErrorAction SilentlyContinue
try {
  Add-DnsServerResourceRecordMX -ZoneName $LabDomain -Name "@" -MailExchange "mail.$LabDomain" -Preference 10 -ErrorAction SilentlyContinue
} catch {}
try {
  Add-DnsServerResourceRecord -ZoneName $LabDomain -Name "@" -TxtData "windows-dns-secondary" -Type TXT -ErrorAction SilentlyContinue
} catch {}

# --- Remote Desktop (so nmap sees 3389/tcp open) ---
Log "enabling Remote Desktop (RDP / 3389)"
try {
  Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
    -Name 'fDenyTSConnections' -Value 0 -Force
  Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
  # Also ensure our explicit rule exists (below)
  Start-Service TermService -ErrorAction SilentlyContinue
  Set-Service TermService -StartupType Automatic -ErrorAction SilentlyContinue
} catch {
  Log "WARN: could not fully enable RDP: $($_.Exception.Message)"
}

# --- Firewall ---
Log "opening firewall 53/80/445/3389"
$rules = @(
  @{ Name = "ENUM-Quest-DNS-UDP"; Proto = "UDP"; Port = 53 },
  @{ Name = "ENUM-Quest-DNS-TCP"; Proto = "TCP"; Port = 53 },
  @{ Name = "ENUM-Quest-HTTP"; Proto = "TCP"; Port = 80 },
  @{ Name = "ENUM-Quest-SMB"; Proto = "TCP"; Port = 445 },
  @{ Name = "ENUM-Quest-RDP"; Proto = "TCP"; Port = 3389 }
)
foreach ($r in $rules) {
  if (-not (Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $r.Name -Direction Inbound -Protocol $r.Proto `
      -LocalPort $r.Port -Action Allow | Out-Null
  }
}

# Enable File and Printer Sharing / SMB if present
Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing" -ErrorAction SilentlyContinue

Log "windows target ready ($WinHost / $LabDomain)"
