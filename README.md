# WaitForUserDeviceRegistration
Pauses device ESP for up to 60 minutes for machine to register with AzureAD.
Add the WaitForUserDeviceRegistration.intunewin app to Intune and specify the following command line:

powershell.exe -noprofile -executionpolicy bypass -file .\WaitForUserDeviceRegistration.ps1

To "uninstall" the app, the following can be used (for example, to get the app to re-install):

cmd.exe /c del %ProgramData%\DeviceRegistration\WaitForUserDeviceRegistration.ps1.tag

Specify the platforms and minimum OS version that you want to support.

For a detection rule, specify the path and file and "File or folder exists" detection method:

%ProgramData%\DeviceRegistration\WaitForUserDeviceRegistration
WaitForUserDeviceRegistration.ps1.tag

Deploy the app as a required app to an appropriate set of devices.
