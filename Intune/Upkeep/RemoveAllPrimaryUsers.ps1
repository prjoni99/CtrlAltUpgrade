<#
.SYNOPSIS
This script remove the primary user from all Windows devices using the Microsoft Graph API.

.DESCRIPTION
The script uses the Microsoft Graph API to connect to a Microsoft 365 tenant, retrieve a list of managed devices, and remove primary users from each device.
The script is set up to authenticate using app credentials and make API calls to endpoints in the Microsoft Graph API.

It uses the following global variables:
- $Global:org - The name of the organization.
- $Global:scriptName - The name of the script.
- $tenantID - The tenant ID.
- $appID - The application ID.
- $secret - The secret key.
- $betaGraphVersion - The Graph API version.
- $baseGraphURL - The Graph API URL.
- $managedDevices - The endpoint for managed devices.
- $betaManagedDevicesUrl - The full URL for the managed devices endpoint.

The script contains two functions:
- Write-Log - Logs messages to a log file.
- Get-AccessToken - Obtains an access token for the Microsoft Graph API.

The script then starts a log, obtains an access token, retrieves a list of devices, and loops through each device to remove its primary users.

.OUTPUTS
The script creates a log file in the specified organization folder and logs the user and device ID for each device it removes the primary user.

.EXAMPLE
.\RemoveAllPrimaryUsers.ps1

.NOTES
I used the app permissions so I could set this as a scheduled task.
Make sure to update the tenant ID, app ID, and secret key with your actual values.
The app you use will need these permissions: 
--DeviceManagementConfiguration.ReadWrite.All: Required to read and write device management configurations.
--DeviceManagementManagedDevices.ReadWrite.All: Required to read and write managed devices.
--DeviceManagementManagedDevices.PrivilegedOperations.All: Required to perform privileged operations on managed devices.
--DeviceManagementServiceConfig.ReadWrite.All: Required to read and write service configurations.
This script was created for use with my organizations resources and expects certain folder structures and file names. Update the variables at the top of the script as necessary to suit your needs.
I prefer an org folder in both ProgramData and AppData so things can stay organized whether running things in the System or User context.

.AUTHOR
Timothy Alexander
https://github.com/taalexander0614/CtrlAltUpgrade
#>

$Global:org = "ORG"
$Global:scriptName = "Remove All Primary Users"
$tenantID = ""
$appID = ""
$secret = ""
$graphURL = "https://graph.microsoft.com"
$graphVersion = "beta"
$baseGraphURL = "$graphURL/$graphVersion"
$managedDevices = "deviceManagement/managedDevices"
$betaManagedDevicesUrl = "$baseGraphURL/$managedDevices"

Function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("DEBUG", "INFO", "WARNING", "ERROR")]
        [string]$Level,       
        [Parameter(Mandatory=$true)]
        [string]$Message
    )
    $orgFolder = "$env:PROGRAMDATA\$org"
    $logFolder = "$orgFolder\Logs"
    $logFile = "$logFolder\$scriptName.log"
    # Create organization folder and log if they don't exist
    If(!(Test-Path $orgFolder)){New-Item $orgFolder -ItemType Directory -Force | Out-Null}
    If(!(Test-Path $logFolder)){New-Item $logFolder -ItemType Directory -Force | Out-Null}
    If(!(Test-Path $logFile)){New-Item $logFile -ItemType File -Force | Out-Null}
    # Set log date stamp
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "$Timestamp [$Level] $Message"
    Add-Content -Path $logFile -Value $logEntry
}

# Function to get the access token using app credentials
function Get-AccessToken {
    Write-Log -Level "INFO" -Message "Obtaining Auth Token"
    $accessTokenUrl = "https://login.microsoftonline.com/$tenantID/oauth2/v2.0/token"
    $tokenRequestBody = @{
        "grant_type"    = "client_credentials"
        "scope"         = "https://graph.microsoft.com/.default"
        "client_id"     = $appID
        "client_secret" = $secret
    }   
    Try {
        $tokenResponse = Invoke-RestMethod -Uri $accessTokenUrl -Method POST -Body $tokenRequestBody
    }
    Catch {
        Write-Log -Level "INFO" -Message "Failed to obtain Auth Token: $_"
    }
    Write-Log -Level "INFO" -Message "Obtained Auth Token"
    return $tokenResponse.access_token
}

# Start the log
Write-Log -Level "INFO" -Message "====================== Start Log ======================"

# Get the auth token
$accessToken = Get-AccessToken -TenantId $tenantID -AppId $appID -ClientSecret $secret

# Construct the authorization header
$authHeaders = @{
    "Authorization" = "Bearer $accessToken"
    "Content-Type" = "application/json"
}

Write-Log -Level "INFO" -Message "Retreiving list of devices"
# Array to store all Windows devices
$devices = @()
$filterParameter = "?`$filter=operatingSystem eq 'Windows'"
$fullUrl = $betaManagedDevicesUrl + $filterParameter
Try {
    $pageCount = 0
    $managedDevicesResponse = (Invoke-RestMethod -Uri $fullUrl -Headers $authHeaders -Method Get) 
    $devices = $managedDevicesResponse.value
    $pageCount++
    Write-Log -Level "INFO" -Message "Retrieved page $pageCount of devices"
    $devicesNextLink = $managedDevicesResponse."@odata.nextLink"
    
    while ($devicesNextLink -ne $null){  
        $managedDevicesResponse = (Invoke-RestMethod -Uri $devicesNextLink -Headers $authHeaders -Method Get)
           $devicesNextLink = $managedDevicesResponse."@odata.nextLink"
        $devices += $managedDevicesResponse.value
        $pageCount++
        Write-Log -Level "INFO" -Message "Retrieved page $pageCount of devices"
    }
    Write-Log -Level "INFO" -Message "Retrieved all pages"
}
Catch {
    Write-Log -Level "ERROR" -Message "Failed to retrieve devices: $_"
}
# Iterate over each managed device and remove primary users
Write-Log -Level "INFO" -Message "Looping through devices to remove primary users"
# Graph API endpoint for removing primary user from a device
$basePrimaryUserURL = "$betaManagedDevicesUrl/{deviceId}/users/"
foreach ($device in $devices) {
    $deviceID = $device.id
    # Remove primary users from the device
    $primaryUserUrl = $basePrimaryUserURL -replace "{deviceId}", $deviceID  
    $primaryUserResponse = (Invoke-RestMethod -Uri $primaryUserUrl -Method GET -Headers $authHeaders).value
    $primaryUser = $primaryUserResponse.displayName
    if ($null -ne $primaryUser) {
        Try {
            Invoke-RestMethod -Uri "$primaryUserUrl`$ref" -Method DELETE -Headers $authHeaders
            Write-Log -Level "INFO" -Message "Removed $primaryUser from $deviceID"
        }
        Catch {
            Write-Log -Level "ERROR" -Message "Failed to remove primary user"
            Write-Log -Level "ERROR" -Message "Error: $_"
        }
    }
}