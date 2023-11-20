# SyncNewAutoPilotComputersandUsersToAAD.ps1
#
# Draft version 2.0
#

# Run this script from the Microsoft Entra Connect (AAD Sync) server

# Enter your OU, or entire domain DN:
$BaseOu = "OU=MyOu,DC=demolab,DC=local"

###################################################################################################

#region 1: Identify computers to sync

Import-module -Name "$env:ProgramFiles\Microsoft Azure AD Sync\Bin\ADSyncDiagnostics\ADSyncDiagnostics.psm1"

$VerbosePreference = "Continue"

# Becuse there could be multiple domains, we want the oldest start time across all AD connectors
$LastSyncCycleStart = (GetADConnectors | sort LastModificationTime | select -First 1).LastModificationTime

# Use the native AdsiSearcher so we don't need the the ActveDirectory PowerShell module (RSAT), 
# which isn't present by default, on an AAD Connect server.
$Searcher = [AdsiSearcher]::new()
$Searcher.SearchRoot = "LDAP://$BaseOu"

# Don't necessarily want to know when created, instead, we want to know when the HAADJ process started (cert date).
# However, if you have a lot of computers, you could use a reasonable time span to limit results.
# $LdapTimeStamp = Get-Date $LastSyncCycleStart -Format yyyyMMddHHmmss.0Z
# $Searcher.Filter = "(&(objectClass=computer)(userCertificate=*)(WhenCreated>=$LdapTimeStamp))"
$Searcher.Filter = "(&(objectClass=computer)(userCertificate=*))"

$SearcherResults = $Searcher.FindAll()
$Searcher.Dispose()

$HaadjInfo = $SearcherResults | foreach {
    $LatestCert = $_.Properties.usercertificate[0]
    $LatestCert_X509 = [Security.Cryptography.X509Certificates.X509Certificate2]::new($LatestCert)
    [pscustomobject]@{
        Computer_DN       = $_.Properties.distinguishedname # case sensitive properties        
        Cert_NotBefore    = $LatestCert_X509.NotBefore
        HasSelfSignedCert = $LatestCert_X509.Issuer -match $_.Properties.ObjectGUID
    }
}

$ComputersToSync = $HaadjInfo | where Cert_NotBefore -gt $LastSyncCycleStart

#endregion 1


#region 2: Sync each new computer

# Wait for any existing sync to stop (Microsoft says to disable the scheduler, but this seems overkill
# https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/how-to-connect-single-object-sync#run-the-single-object-sync-tool
while ((Get-ADSyncScheduler).SyncCycleInProgress) {
    Write-Verbose "SyncCycleInProgress - waiting 15 seconds"
    sleep 15    
}

$AADConnector = GetAADConnector
# Microsoft also asks that we wait 5 minutes between Entra export or import
# : https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/how-to-connect-single-object-sync#single-object-sync-throttling
$5MinutesFromNow = (Get-Date).AddMinutes(5)
while ($AADConnector.LastModificationTime -lt $5MinutesFromNow) {
    Write-Verbose "Microsoft asks we wait 5 minutes between exports - waiting one minute."
    sleep 60    
}

foreach ($Computer in $ComputersToSync) {
    Invoke-ADSyncSingleObjectSync -DistinguishedName $Computer.Computer_DN -NoHtmlReport -StagingMode # | ConvertFrom-Json
}

#endregion 2