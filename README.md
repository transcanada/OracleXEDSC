This repository contains a PowerShell module with a DSC resource that can be used to install Oracle XE.

## Sample

First, ensure the OracleDSC module is on your `$env:PSModulePath`. Then you can create and apply configuration like this.

```
Configuration SampleConfig
{
    Import-DscResource -Module OracleXEDSC
 
    Node "localhost"
    {
        cOracleXE OracleXE 
        { 
            Ensure = "Present" 
            State = "Started"
            
            # Leave as OracleXE             
            Name = "OracleXE"
 
            # The url to dowload the Oracle XE installation zip file
            InstallationZipUrl = "http://someserver/OracleXE112_Win64.zip"
            
            # The password to configure Oracle XE system account with
            OracleSystemPassword = "somepassword"            
        }
    }
}
 
SampleConfig -InstallationZipUrl "http://someserver/OracleXE112_Win64.zip" -OracleSystemPassword "somepassword"

Start-DscConfiguration .\SampleConfig -Verbose -wait

Test-DscConfiguration
```

## Settings

When `Ensure` is set to `Present`, the resource will:

 1. Download the Oracle XE Zip from the internet
 2. Configure Oracle XE install with desired system account password
 3. Install Oracle XE 

When `Ensure` is set to `Absent`, the resource will throw an error as uninstall of Oracle XE is not supported by module yet.

When `State` is `Started`, the resource will ensure that the Oracle XE windows services 'OracleServiceXE' and 'OracleXETNSListener' are running. When `Stopped`, it will ensure all Oracle XE services are stopped.


