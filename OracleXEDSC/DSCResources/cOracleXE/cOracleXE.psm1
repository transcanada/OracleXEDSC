function Get-TargetResource
{
    [OutputType([Hashtable])]
    param (
        [ValidateSet("Present", "Absent")]
        [string]$Ensure = "Present",
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [ValidateSet("Started", "Stopped")]
        [string]$State = "Started",                
        [string]$InstallationZipUrl,
        [string]$OracleSystemPassword
    )

    Write-Verbose "Checking if Oracle is installed"
    $installLocation = (get-itemproperty -path "HKLM:\Software\ORACLE\KEY_XE" -ErrorAction SilentlyContinue).ORACLE_HOME
    $present = ($installLocation -ne $null)
    Write-Verbose "Oracle XE present: $present"
    
    $currentEnsure = if ($present) { "Present" } else { "Absent" }

    $serviceName = (Get-OracleXEServiceNames)[0]
    Write-Verbose "Checking for Windows Service: $serviceName"
    $serviceInstance = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    $currentState = "Stopped"
    if ($serviceInstance -ne $null) 
    {
        Write-Verbose "Windows service: $($serviceInstance.Status)"
        if ($serviceInstance.Status -eq "Running") 
        {
            $currentState = "Started"
        }
        
        if ($currentEnsure -eq "Absent") 
        {
            Write-Verbose "Since the Windows Service is still installed, the service is present"
            $currentEnsure = "Present"
        }
    } 
    else 
    {
        Write-Verbose "Windows service: Not installed"
        $currentEnsure = "Absent"
    }

    return @{
        Name = $Name; 
        Ensure = $currentEnsure;
        State = $currentState;
    };
}

function Set-TargetResource 
{
    param (       
        [ValidateSet("Present", "Absent")]
        [string]$Ensure = "Present",
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [ValidateSet("Started", "Stopped")]
        [string]$State = "Started",        
        [Parameter(Mandatory)]        
        [string]$InstallationZipUrl,
        [Parameter(Mandatory=$True)]
        [string]$OracleSystemPassword 
    )

    if ($Ensure -eq "Absent" -and $State -eq "Started") 
    {
        throw "Invalid configuration: service cannot be both 'Absent' and 'Started'"
    }

    $currentResource = (Get-TargetResource -Name $Name)

    Write-Verbose "Configuring Oracle XE ..."

    $serviceNames = Get-OracleXEServiceNames
        
    if ($State -eq "Stopped" -and $currentResource["State"] -eq "Started") 
    {        
        Write-Verbose "Stopping Oracle XE services..."
        foreach ($serviceName in $serviceNames) {
	       Write-Verbose "Stopping $serviceName"
           Stop-Service -Name $serviceName -Force
        }        
    }

    if ($Ensure -eq "Absent" -and $currentResource["Ensure"] -eq "Present")
    {                
        # Uninstall Oracle XE
        throw "Removal of Oracle XE Currently not supported by this DSC Module!"        
    } 
    elseif ($Ensure -eq "Present" -and $currentResource["Ensure"] -eq "Absent") 
    {
        Write-Verbose "Installing Oracle XE..."
        Install-OracleXE -InstallationZipUrl $InstallationZipUrl -OracleSystemPassword $OracleSystemPassword
        Write-Verbose "Oracle XE installed!"
    }

    if ($State -eq "Started" -and $currentResource["State"] -eq "Stopped") 
    {
        $serviceNames = Get-OracleXEServiceNamesThatShouldBeRunning
        Write-Verbose "Starting Oracle XE services..."
        foreach ($serviceName in $serviceNames) {
            Write-Verbose "Starting $serviceName"
            Start-Service -Name $serviceName
        }                  
    }

    Write-Verbose "Finished"
}

function Test-TargetResource 
{
    param (       
        [ValidateSet("Present", "Absent")]
        [string]$Ensure = "Present",
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [ValidateSet("Started", "Stopped")]
        [string]$State = "Started",                
        [string]$InstallationZipUrl,
        [string]$OracleSystemPassword
    )
 
    $currentResource = (Get-TargetResource -Name $Name)

    $ensureMatch = $currentResource["Ensure"] -eq $Ensure
    Write-Verbose "Ensure: $($currentResource["Ensure"]) vs. $Ensure = $ensureMatch"
    if (!$ensureMatch) 
    {
        return $false
    }
    
    $stateMatch = $currentResource["State"] -eq $State
    Write-Verbose "State: $($currentResource["State"]) vs. $State = $stateMatch"
    if (!$stateMatch) 
    {
        return $false
    }

    return $true
}

function Get-OracleXEServiceNames 
{
    return @('OracleServiceXE','OracleXETNSListener','OracleJobSchedulerXE','OracleMTSRecoveryService','OracleXEClrAgent')
}

function Get-OracleXEServiceNamesThatShouldBeRunning 
{
    return @('OracleServiceXE','OracleXETNSListener')
}

function Request-File 
{
    param (
        [string]$url,
        [string]$saveAs
    )
 
    Write-Verbose "Downloading $url to $saveAs"
    $downloader = new-object System.Net.WebClient
    $downloader.DownloadFile($url, $saveAs)
}

function Invoke-AndAssert {
    param ($block) 
  
    & $block | Write-Verbose
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) 
    {
        throw "Command returned exit code $LASTEXITCODE"
    }
}

function Expand-ZipFile
{
    param (
        [string]$file, 
        [string]$destination
    )    
    Add-Type -assembly "system.io.compression.filesystem"
    [io.compression.zipfile]::ExtractToDirectory($file, $destination)
}
  
function Install-OracleXE 
{
    param (
        [Parameter(Mandatory=$True)]
        [string]$InstallationZipUrl,
        [Parameter(Mandatory=$True)]
        [string]$OracleSystemPassword                        
    )
 
    $installTempDir = 'c:\windows\temp'
    $installZipPath = "$installTempDir\Oracle_XE_11G_R2.zip"
    $installTempPath = "$installTempDir\Oracle_XE_11G_R2"
    $installExecutable = $installTempPath + '\DISK1\setup.exe'
    $oracleInstallFile = "$($installTempPath)\DISK1\response\OracleXE-install_replaced.iss"
    $installLogFile = "$installTempPath\setup.log"
    $installArguments = '/s /f1"' + $oracleInstallFile + '" /f2"' + $installLogFile + '"'    

    Remove-Item $installTempPath -recurse -erroraction silentlycontinue
    $installationZipFilePath = "$installTempDir\Oracle.msi"
    if ((test-path $installZipPath) -ne $true) 
    {
        Write-Verbose "Downloading Oracle XE installation zip from $InstallationZipUrl to $installZipPath"
        Request-File $InstallationZipUrl $installZipPath
        Write-Verbose "Downloaded Oracle XE installation zip to $installZipPath"
    }
    
    Write-Verbose "Expanding Oracle XE installation zip $installZipPath to directory $installTempPath"
    Expand-ZipFile $installZipPath $installTempPath
    Write-Verbose "Expanded Oracle XE installation zip to directory $installTempPath"
        
    Write-Verbose "Configuring Oracle XE with system password before installation."
    (cat "$($installTempPath)\DISK1\response\OracleXE-install.iss") -replace 'SYSPassword=oraclexe', "SYSPassword=$OracleSystemPassword" > $oracleInstallFile    
    
    Write-Verbose "Starting install of Oracle XE."
    Start-Process -FilePath $installExecutable -ArgumentList $installArguments -Wait -Passthru
    Write-Verbose "Finished install of Oracle XE."        
}
