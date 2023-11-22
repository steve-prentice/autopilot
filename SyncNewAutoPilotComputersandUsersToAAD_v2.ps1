<#
    .SYNOPSIS
    Triggers an Entra Connect (AAD Connect) "Single Object Sync" so that computers
    do not have to wait for the default Entra Connect synchronization interval.

    .DESCRIPTION
    As discussed in https://github.com/steve-prentice/autopilot/issues/4, 
    Microsoft doesn't want customers running Entra Connect Sync more frequently
    than their AllowedSyncCycleInterval, which is currently 30 minutes.
    However, this results in a significant delay in the AutoPilot/OOBE experience
    for Hybrid Azure AD Joined workstations.

    This script looks for computers in a given OU ($BaseOu) with a certificate
    generated more recently than the last Entra sync cycle, as the certificate's
    date is representative of workstations Entra join attempt.

    Run this script every 5 minutes, as a scheduled task from the Microsoft Entra
    Connect (AAD Connect) server.

    See the README file for an explanation on using this script with
    WaitForUserDeviceRegistration.ps1, which runs on the workstations themselves.

    .NOTES
    File Name      : SyncNewAutoPilotComputersandUsersToAAD.ps1
    Prerequisite   : ADSync and ADSyncDiagnostics module (installed by default)
    Version        : 2.0
    Link           : https://github.com/steve-prentice/autopilot
    Contributors   : Alex Durrant, Steve Prentice, Mike Crowley

    .FUTURE
    -To-do item 1  : Add logic to cap the syncs at a specific number of devices, 
    failing back to normal delta import/sync.
#>

# Enter your OU, or entire domain DN:
$BaseOu = "OU=MyOu,DC=demolab,DC=local"

###################################################################################################

#region 1: Identify computers to sync

Import-Module -Name "$env:ProgramFiles\Microsoft Azure AD Sync\Bin\ADSyncDiagnostics\ADSyncDiagnostics.psm1"

$VerbosePreference = "Continue"

# Get the most recent import/sync/export results
$PreviousSyncResults = GetADConnectors | ForEach-Object { Get-ADSyncRunProfileResult -ConnectorId $_.Identifier -NumberRequested 3 }
# Becuse there could be multiple domains, we want the oldest start time across all AD connectors
$LastSyncCycleStart = (($PreviousSyncResults.startdate | Sort-Object)[0]).ToLocalTime()

# Use the native AdsiSearcher so we don't need the the ActveDirectory PowerShell module (RSAT), 
# which isn't present by default, on an AAD Connect server.
$Searcher = [AdsiSearcher]::new()
$Searcher.SearchRoot = "LDAP://$BaseOu"

# Don't necessarily want to know when created, instead, we want to know when the HAADJ process started (cert date).
# However, if you have a lot of computers, you could use a reasonable time span to limit results.
# $LdapTimeStamp = Get-Date $LastSyncCycleStart -Format yyyyMMddHHmmss.0Z
# $Searcher.Filter = "(&(objectClass=computer)(userCertificate=*)(WhenCreated>=$LdapTimeStamp))"
$Searcher.Filter = "(&(objectClass=computer)(userCertificate=*))"

$ErrorActionPreference = "SilentlyContinue"
$SearcherResults = $Searcher.FindAll() 
$Searcher.Dispose()
$ErrorActionPreference = "Continue"

If ($SearcherResults.Count -ge 1) {
    $HaadjInfo = $SearcherResults | ForEach-Object {
        $LatestCert_X509 = [Security.Cryptography.X509Certificates.X509Certificate2]$_.Properties.usercertificate[0]
        [pscustomobject]@{
            Computer_DN    = [string]$_.Properties.distinguishedname # case sensitive properties        
            Cert_NotBefore = $LatestCert_X509.NotBefore        
        }
    }

    [array]$ComputersToSync = $HaadjInfo | Where-Object Cert_NotBefore -gt $LastSyncCycleStart
}
Else {
    Write-Verbose "`nSkipping Region 1 - There are no computers to sync." 
    Write-Verbose "If you would like to create test accounts, use New-TestComputer"
    Write-Verbose "https://github.com/steve-prentice/autopilot/issues/4#issuecomment-1819868383"
}

#endregion 1


#region 2: Sync each new computer

If ($ComputersToSync.Count -ge 1) {

    # Wait for any existing sync to stop (Microsoft says to disable the scheduler, but this seems overkill
    # https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/how-to-connect-single-object-sync#run-the-single-object-sync-tool
    while ((Get-ADSyncScheduler).SyncCycleInProgress) {
        Write-Verbose "SyncCycleInProgress - waiting 15 seconds"
        Start-Sleep 15    
    }

    $AADConnectorLastEnd = (Get-ADSyncRunProfileResult -ConnectorId (GetAADConnector).Identifier -NumberRequested 1).EndDate.ToLocalTime()
    # Microsoft also asks that we wait 5 minutes between Entra export or import
    # : https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/how-to-connect-single-object-sync#single-object-sync-throttling

    while ((Get-Date) -lt $AADConnectorLastEnd.AddMinutes(5)) {
        Write-Verbose "AAD Connector just ran at $AADConnectorLastEnd"
        Write-Verbose "Microsoft asks we wait 5 minutes between exports - waiting until: $($AADConnectorLastEnd.AddMinutes(5))."
        Start-Sleep 15    
    }

    $ComputersToSync | ForEach-Object {
        Invoke-ADSyncSingleObjectSync -DistinguishedName $_.Computer_DN -NoHtmlReport | ConvertFrom-Json
    }
}
Else { Write-Verbose "`nSkipping Region 2 - There are no computers to sync." }

#endregion 2