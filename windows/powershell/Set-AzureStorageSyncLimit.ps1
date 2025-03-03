# Storage Sync Network Limit Automation Script
# This script connects to multiple file servers and configures storage sync network limits
# Usage: .\upload-limit.ps1 60000

param(
    [Parameter(Mandatory=$true)]
    [int]$LimitKbps
)

# List of file servers to connect to
$fileservers = 'server_name_1','server_name_2','etc'

# Function to set storage sync network limits on a server
function Set-ServerStorageSyncLimits {
    param (
        [string]$ServerName,
        [int]$LimitKbps
    )
    
    try {
        Write-Host "Connecting to $ServerName..." -ForegroundColor Cyan
        
        # Test if server is reachable before attempting to connect
        if (-not (Test-WSMan -ComputerName $ServerName -ErrorAction Stop)) {
            throw "Cannot connect to server using WS-Management"
        }
        
        # Use Invoke-Command to run commands remotely on the target server
        $result = Invoke-Command -ComputerName $ServerName -ScriptBlock {
            param($LimitKbps)
            
            # Import the required module
            Import-Module "C:\Program Files\Azure\StorageSyncAgent\StorageSync.Management.ServerCmdlets.dll" -ErrorAction Stop
            
            # Get existing network limits
            $existingLimits = Get-StorageSyncNetworkLimit
            
            # Check if existing limits already match the desired configuration
            $changeRequired = $false
            
            if ($existingLimits) {
                Write-Host "Checking existing network limits..." -ForegroundColor Yellow
                Write-Host "Current desired limit: $LimitKbps Kbps" -ForegroundColor Yellow
                
                # Display existing limits
                Write-Host "Existing limits:" -ForegroundColor Yellow
                $existingLimits | ForEach-Object {
                    Write-Host "  - ID: $($_.Id), Limit: $($_.LimitKbps) Kbps, Days: $($_.Day -join ', '), Hours: $($_.StartHour)-$($_.EndHour)" -ForegroundColor Gray
                }
                
                # First check: All limits must match desired Kbps
                foreach ($limit in $existingLimits) {
                    if ($limit.LimitKbps -ne $LimitKbps) {
                        Write-Host "  Found mismatched limit: $($limit.LimitKbps) Kbps (desired: $LimitKbps Kbps)" -ForegroundColor Yellow
                        $changeRequired = $true
                        break
                    }
                }
                
                # If Kbps values match, check for full coverage differently
                if (-not $changeRequired) {
                    Write-Host "  All limits have correct Kbps value, checking full coverage..." -ForegroundColor Yellow
                    
                    # Skip complex coverage checks if we have exactly 7 rules with correct limits
                    # Ensure each day has a rule covering the full 0-23 hour range
                    $allDays = @('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')
                    $coveredDays = @{}
                    
                    # Initialize all days as not covered
                    foreach ($day in $allDays) {
                        $coveredDays[$day] = $false
                    }
                    
                    # Check that we have the right number of rules
                    if ($existingLimits.Count -eq 7) {
                        Write-Host "  Found 7 rules - checking coverage for each day..." -ForegroundColor Yellow
                        
                        # Mark each day directly based on the rules we find
                        foreach ($day in $allDays) {
                            # Look for a rule for this day with full coverage
                            $dayRule = $existingLimits | Where-Object { 
                                $_.Day -eq $day -and $_.StartHour -eq 0 -and $_.EndHour -eq 23 
                            }
                            
                            if ($dayRule) {
                                Write-Host "  Found complete rule for $day (StartHour: 0, EndHour: 23)" -ForegroundColor Green
                                $coveredDays[$day] = $true
                            } else {
                                Write-Host "  Missing complete rule for $day" -ForegroundColor Yellow
                            }
                        }
                        
                        # Check if all days are covered
                        $missingDays = @($allDays | Where-Object { -not $coveredDays[$_] })
                        
                        if ($missingDays.Count -eq 0) {
                            # All days have rules with full coverage
                            Write-Host "  SUCCESS: All days have correct coverage (0-23 hours)" -ForegroundColor Green
                            $fullCoverage = $true
                        } else {
                            Write-Host "  Missing full coverage for days: $($missingDays -join ', ')" -ForegroundColor Yellow
                            $fullCoverage = $false
                        }
                    } else {
                        # Wrong number of rules
                        Write-Host "  Expected 7 rules (one per day), found $($existingLimits.Count)" -ForegroundColor Yellow
                        $fullCoverage = $false
                    }
                    
                    if (-not $fullCoverage) {
                        $changeRequired = $true
                        Write-Host "  Need to update: Incomplete day/hour coverage" -ForegroundColor Yellow
                    }
                }
                
                if (-not $changeRequired) {
                    Write-Host "  SUCCESS: Current network limits already set to $LimitKbps Kbps for all days and hours." -ForegroundColor Green
                    Write-Host "  No changes needed." -ForegroundColor Green
                    return @{
                        Success = $true
                        Message = "No configuration changes needed - already set to desired value"
                        ChangesMade = $false
                    }
                } else {
                    Write-Host "  Changes required: Will update network limits to $LimitKbps Kbps" -ForegroundColor Yellow
                }
            } else {
                # No existing limits found, so changes are required
                $changeRequired = $true
                Write-Host "  No existing limits found - will create new limits" -ForegroundColor Yellow
            }
            
            if ($changeRequired) {
                # Remove existing limits if any exist
                if ($existingLimits) {
                    Write-Host "Removing existing network limits..." -ForegroundColor Yellow
                    $existingLimits | ForEach-Object { 
                        Remove-StorageSyncNetworkLimit -Id $_.Id 
                        Write-Host "  Removed limit with ID: $($_.Id)" -ForegroundColor Gray
                    }
                } else {
                    Write-Host "  No existing limits found" -ForegroundColor Gray
                }
                
                # Create new network limits
                Write-Host "Creating new network limit ($LimitKbps Kbps for all days, all hours)..." -ForegroundColor Green
                try {
                    # Create individual rules for each day (follows the pattern observed in existing config)
                    foreach ($day in @('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')) {
                        Write-Host "  Creating rule for $day..." -ForegroundColor Gray
                        New-StorageSyncNetworkLimit -Day $day -StartHour 0 -EndHour 23 -LimitKbps $LimitKbps | Out-Null
                    }
                    
                    # Simple verification - just check if any limits exist now
                    $newLimits = Get-StorageSyncNetworkLimit
                    if ($newLimits -and $newLimits.Count -gt 0) {
                        Write-Host "New limits configured successfully." -ForegroundColor Green
                        
                        return @{
                            Success = $true
                            Message = "Configuration completed successfully"
                            ChangesMade = $true
                        }
                    } else {
                        throw "Failed to create network limits: No limits found after creation"
                    }
                } catch {
                    throw "Failed to create new network limit: $_"
                }
            }
        } -ArgumentList $LimitKbps -ErrorAction Stop
        
        # If we reached here, the command completed successfully
        $statusMsg = if ($result.ChangesMade) { "Successfully configured" } else { "Already configured correctly on" }
        Write-Host "$statusMsg $ServerName" -ForegroundColor Green
        Write-Host "----------------------------------------" -ForegroundColor DarkGray
        return $true
    }
    catch {
        # Handle various types of errors
        $errorMessage = $_.Exception.Message
        
        # Check for access denied errors specifically
        if ($errorMessage -match "Access is denied" -or $errorMessage -match "AccessDenied") {
            Write-Host "Error configuring $ServerName - Access Denied" -ForegroundColor Red
            Write-Host "This may require running as administrator or checking permissions" -ForegroundColor Yellow
        } else {
            Write-Host "Error configuring $ServerName" -ForegroundColor Red
            Write-Host "Error details: $errorMessage" -ForegroundColor Red
        }
        
        Write-Host "----------------------------------------" -ForegroundColor DarkGray
        return $false
    }
}

# Variables to track progress
$totalServers = $fileservers.Count
$successful = 0
$failed = 0
$failedServers = @()
$startTime = Get-Date

# Display script header
Write-Host "=====================================================" -ForegroundColor Blue
Write-Host "  STORAGE SYNC NETWORK LIMIT AUTOMATION" -ForegroundColor Blue
Write-Host "  Total servers to configure: $totalServers" -ForegroundColor Blue
Write-Host "  Target bandwidth limit: $LimitKbps Kbps" -ForegroundColor Blue
Write-Host "  Starting time: $startTime" -ForegroundColor Blue
Write-Host "=====================================================" -ForegroundColor Blue
Write-Host ""

# Process each server
foreach ($server in $fileservers) {
    $result = Set-ServerStorageSyncLimits -ServerName $server -LimitKbps $LimitKbps
    
    if ($result) {
        $successful++
    } else {
        $failed++
        $failedServers += $server
    }
}

# Display summary
$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host "=====================================================" -ForegroundColor Blue
Write-Host "  SUMMARY" -ForegroundColor Blue
Write-Host "  Target bandwidth limit: $LimitKbps Kbps" -ForegroundColor Blue
Write-Host "  Total servers processed: $totalServers" -ForegroundColor Blue
Write-Host "  Successful: $successful" -ForegroundColor Green
Write-Host "  Failed: $failed" -ForegroundColor $(if ($failed -gt 0) {"Red"} else {"Green"})
if ($failed -gt 0) {
    Write-Host "  Failed servers: $($failedServers -join ", ")" -ForegroundColor Red
}
Write-Host "  Duration: $($duration.Minutes) minutes, $($duration.Seconds) seconds" -ForegroundColor Blue
Write-Host "  Completed at: $endTime" -ForegroundColor Blue
Write-Host "=====================================================" -ForegroundColor Blue

# Export results to log file in the same directory as the script
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
# If running in ISE or directly from console, use current directory
if (!$scriptDirectory) {
    $scriptDirectory = Get-Location
}
$logPath = Join-Path -Path $scriptDirectory -ChildPath "StorageSyncAutomation_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Create log file
"Storage Sync Network Limit Automation completed at $(Get-Date)" | Out-File -FilePath $logPath
"Target bandwidth limit: $LimitKbps Kbps" | Out-File -FilePath $logPath -Append
"Servers processed: $totalServers, Successful: $successful, Failed: $failed" | Out-File -FilePath $logPath -Append
if ($failed -gt 0) {
    "Failed servers: $($failedServers -join ", ")" | Out-File -FilePath $logPath -Append
}

Write-Host "  Log file created at: $logPath" -ForegroundColor Blue