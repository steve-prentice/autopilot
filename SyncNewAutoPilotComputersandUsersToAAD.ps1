# SyncNewAutoPilotComputersandUsersToAAD.ps1
#
# Version 1.4
#
# Stolen from Alex Durrant. Updated by Steve Prentice, 2020
#
# Triggers an ADDConnect Delta Sync if new objects are found to be have been created
# in the OU's in question, this is helpful with Hybrid AD joined devices via Autopilot
# and helps to avoid the 3rd authentication prompt.
#
# Only devices with a userCertificate attribute are synced, so this script only attempts
# to sync devices that have this attribute updated in the last 5 minutes and have the attribute set,
# which is checked every 5 minutes via any changes in the object's Modified time.
#
# Install this as a scheduled task that runs every 5 minutes on your AADConnect server.
# Change the OU's to match your environment.

Import-Module ActiveDirectory

$time = [DateTime]::Now.AddMinutes(-5)
$computers = Get-ADComputer -Filter 'Modified -ge $time' -SearchBase "OU=AutoPilotDevices,OU=Computers,DC=somedomain,DC=com" -Properties Modified, userCertificate
$users = Get-ADUser -Filter 'Created -ge $time' -SearchBase "OU=W10Users,OU=Users,DC=somedomain,DC=com" -Properties Created
$dc = Get-ADDomainController -Discover

If ($null -ne $computers) {
    ForEach ($computer in $computers) {
        $replicationmetadata = Get-ADReplicationAttributeMetadata -Object $computer -Server $dc -Properties userCertificate
        If (($replicationmetadata.LastOriginatingChangeTime -ge $time) -And ($computer.userCertificate)) {
            # The below adds to AD groups automatically if you want
            #Add-ADGroupMember -Identity "Some Intune Co-management Pilot Device Group" -Members $computer
            $syncComputers = "True"
        }
    }
    # Wait for 30 seconds to allow for some replication
    Start-Sleep -Seconds 30
}

If (($null -ne $syncComputers) -Or ($null -ne $users)) {
    Try { Start-ADSyncSyncCycle -PolicyType Delta }
    Catch {}
}
