$AssetName              = "10.0.1515.98-PQU-2"                      # Name of software deployable package in LCS asset library (e.g. "10.0.1515.98-PQU-2")
$TargetEnvironmentName  = "..."                                     # Environment name  (e.g. "my-dev-machine")
$UpdateType             = "PQU"                                     # "PQU" (Proactive Quality Update) or "SU" (Service Update)
$LCS_ApiUri             = "https://lcsapi.lcs.dynamics.com"
$LCS_ProjectId          = "..."
$LCS_ClientId           = "..."
$LCS_Username           = "..."
$LCS_Password           = "..."

# Cmdlet to print current timestamp
function Get-Timestamp {
    return Get-Date -Format "[HH:mm:ss] -"
}

# Authentication
Write-Host "$(Get-Timestamp) Authenticating to LCS API..."
Get-D365LcsApiToken -ClientId $LCS_ClientId `
                    -Username $LCS_Username `
                    -Password $LCS_Password `
                    -LcsApiUri $LCS_ApiUri | Set-D365LcsApiConfig -ProjectId $LCS_ProjectId -ClientId $LCS_ClientId

# Get environment info
$TargetEnvironment = Get-D365LcsEnvironmentMetadata -EnvironmentName $TargetEnvironmentName

if ($null -eq $TargetEnvironment) {
    Write-Host "$(Get-Timestamp) Unable to find LCS environment $($TargetEnvironmentName), exiting..."
    Exit 1;
}

Write-Host "Target environment:"
Write-Host "*******************"
$TargetEnvironment

# Asset info
$Asset = Get-D365LcsAssetFile -AssetName $AssetName

if ($null -eq $Asset) {
    Write-Host "$(Get-Timestamp) Unable to find asset $($AssetName) within LCS asset library, exiting..."
    Exit 1;
}

Write-Host "Asset to deploy:"
Write-Host "****************"
$Asset

# Get PQU build info
$FileName = $Asset.FileName
$BuildNumber = $FileName.Split("_")[1]
$BuildNumberArray = $BuildNumber.Split(".")
$ServiceUpdatePQU = $BuildNumberArray[0] + "." + $BuildNumberArray[1] + "." + $BuildNumberArray[2]
$HotfixVersionPQU = $BuildNumberArray[3]
Write-Host "Package info:"
Write-Host "*************"
Write-Host "Build number: $($BuildNumber)"
Write-Host "Service update: $($ServiceUpdatePQU)"
Write-Host "Hotfix: $($HotfixVersionPQU)"

# Get env build version
$BuildNumberArray = $TargetEnvironment.CurrentApplicationBuildVersion.Split(".")
$ServiceUpdateEnv = $BuildNumberArray[0] + "." + $BuildNumberArray[1] + "." + $BuildNumberArray[2]
$HotfixVersionEnv = $BuildNumberArray[3]

# Check prerequisites
if ( ($ServiceUpdateEnv -ne $ServiceUpdatePQU) -and ($UpdateType -eq "PQU") ) {
    # Environment is running on a different service update and is not a service update, cancel update
    Write-Host "PQU service update != environment service update, cancelling..."
    Write-Host "PQU: $($ServiceUpdatePQU)"
    Write-Host "env: $($ServiceUpdateEnv)"
}
elseif ( ($HotfixVersionPQU -le $HotfixVersionEnv) -and ($UpdateType -eq "PQU") ) {
    # Environment is running on the same / newer version, cancel update
    Write-Host "PQU version has a lower build version compared to the current environment, cancelling..."
    Write-Host "PQU: $($HotfixVersionPQU)"
    Write-Host "env: $($HotfixVersionEnv)"
}
else {
    # Start VM
    # VM is currently stopped, start it
    if ($TargetEnvironment.CanStart) { 
        Write-Host "$(Get-Timestamp) Starting VM $($TargetEnvironmentName)..."
        Invoke-D365LcsEnvironmentStart -EnvironmentId $TargetEnvironment.EnvironmentId > $null
        Start-Sleep -Seconds 180
        $StopVirtualMachinePostUpdate = $true
    }
    # VM was already started, don't stop VM post-update (e.g. test environment)
    else {
        $StopVirtualMachinePostUpdate = $false
    }
    
    # Apply PQU
    $EnvStatus = Get-D365LcsEnvironmentMetadata -EnvironmentId $TargetEnvironment.EnvironmentId

    if ($EnvStatus.DeploymentStatusDisplay -eq "Deployed") {
        Write-Host "$(Get-Timestamp) Deploying asset '$($AssetName)' to environment '$($TargetEnvironmentName)'..."
        $DeploymentOperation = Invoke-D365LcsDeployment -AssetId $Asset.Id -EnvironmentId $TargetEnvironment.EnvironmentId
        write-host "***************** DeploymentOperation ********************"
        write-host $DeploymentOperation
        write-host "**********************************************************"
        if ($DeploymentOperation.IsSuccess -eq "True") {
            # Succesfully invoked deployment (!= actual update)
            Write-Host "$(Get-Timestamp) Successfully started deployment of asset '$($AssetName)' to environment '$($TargetEnvironmentName)' with activity id '$($DeploymentOperation.ActivityId)'"
            Write-Host "$(Get-Timestamp) Waiting for deployment to complete..."
            $DeploymentStatus = Get-D365LcsDeploymentStatus -ActivityId $DeploymentOperation.ActivityId -EnvironmentId $TargetEnvironment.EnvironmentId -SleepInSeconds 0
            Write-Host "$(Get-Timestamp) Status: $($DeploymentStatus.OperationStatus)"

            # Poll deployment status every 5 min, timeout after 6 hours
            while ( ($DeploymentStatus.OperationStatus -ne "Completed") -and ($DeploymentPollingCount -lt 72) ) {
                # Refresh the access token
                Get-D365LcsApiConfig | Invoke-D365LcsApiRefreshToken | Set-D365LcsApiConfig

                # Check deployment progress
                $DeploymentStatus = Get-D365LcsDeploymentStatus -ActivityId $DeploymentOperation.ActivityId -EnvironmentId $TargetEnvironment.EnvironmentId -SleepInSeconds 300
                Write-Host "$(Get-Timestamp) Status: $($DeploymentStatus.OperationStatus)"
                $DeploymentPollingCount++
            } 
            
            # Check deployment outcome
            if ($DeploymentStatus.OperationStatus -eq "Completed") {
                Write-Host "$(Get-Timestamp) Successfully deployed asset '$($AssetName)' to environment '$($TargetEnvironmentName)' with activity id '$($DeploymentOperation.ActivityId)'"
                $DeploymentStatus
                Start-Sleep -Seconds 180
            }
            else {
                # Deployment timed out, something went wrong
                Write-Host "$(Get-Timestamp) Updating environment $($TargetEnvironmentName) exceeded 6 hour timeout."
                $DeploymentStatus
                $StopVirtualMachinePostUpdate = $false
            }

        }
        else {
            # Unable to invoke deployment
            Write-Host "$(Get-Timestamp) Invoking deployment on environment $($TargetEnvironmentName) has failed..."
            Write-Host "$(Get-Timestamp) Status: $($DeploymentOperation.ErrorMessage)"
            write-error "$(Get-Timestamp) execution stopped" -ErrorAction Stop
        }
    }

    # Stop VM
    $TargetEnvironment = Get-D365LcsEnvironmentMetadata -EnvironmentName $TargetEnvironmentName

    if ( $TargetEnvironment.CanStop -and $StopVirtualMachinePostUpdate ) {
        Write-Host "$(Get-Timestamp) Stopping VM $($TargetEnvironmentName) "
        Invoke-D365LcsEnvironmentStop -EnvironmentId $TargetEnvironment.EnvironmentId > $null
    }
}
