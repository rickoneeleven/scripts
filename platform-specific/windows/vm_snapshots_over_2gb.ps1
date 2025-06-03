# Check if the environment variable exists
if (-not [System.Environment]::GetEnvironmentVariable("VCENTER_SERVER", "User")) {
    Write-Host "Error: VCENTER_SERVER environment variable is not set." -ForegroundColor Red
    Write-Host "Please set it using the following commands in an elevated PowerShell prompt. 1st makes it persistent across sessions, 2nd makes it work now: " -ForegroundColor Yellow
    Write-Host '[System.Environment]::SetEnvironmentVariable("VCENTER_SERVER", "your-vcenter-server.com", "User")' -ForegroundColor Yellow
    Write-Host '$env:VCENTER_SERVER = "your-vcenter-server.com"' -ForegroundColor Yellow
    exit 1
}

# Use the environment variable
$vcenterServer = [System.Environment]::GetEnvironmentVariable("VCENTER_SERVER", "User")

# Connect to the vCenter server using the environment variable
try {
    Connect-VIServer -Server $vcenterServer -ErrorAction Stop
} catch {
    Write-Host "Error: Failed to connect to vCenter server. Please check your server name and credentials." -ForegroundColor Red
    exit 1
}

# Get all VMs
$vms = Get-VM

# Initialize an array to store results
$results = @()

foreach ($vm in $vms) {
    $snapshots = Get-Snapshot -VM $vm

    foreach ($snapshot in $snapshots) {
        $sizeGB = [math]::Round($snapshot.SizeGB, 2)
        
        # Only process snapshots larger than 2GB
        if ($sizeGB -gt 2) {
            # Use Task log SDK to get the user who created the Snapshot
            $TaskMgr = Get-View TaskManager
            $Filter = New-Object VMware.Vim.TaskFilterSpec
            $Filter.Time = New-Object VMware.Vim.TaskFilterSpecByTime
            $Filter.Time.beginTime = ((($snapshot.Created).AddSeconds(-5)).ToUniversalTime())
            $Filter.Time.timeType = "startedTime"
            $Filter.Time.EndTime = ((($snapshot.Created).AddSeconds(5)).ToUniversalTime())
            $Filter.State = "success"
            $Filter.Entity = New-Object VMware.Vim.TaskFilterSpecByEntity
            $Filter.Entity.recursion = "self"
            $Filter.Entity.entity = $vm.Extensiondata.MoRef

            $TaskCollector = Get-View ($TaskMgr.CreateCollectorForTasks($Filter))
            $TaskCollector.RewindCollector | Out-Null
            $Tasks = $TaskCollector.ReadNextTasks(100)
            
            $SnapUser = ""
            foreach ($Task in $Tasks) {
                if ($Task.DescriptionId -eq "VirtualMachine.createSnapshot" -and $Task.State -eq "success" -and $Task.EntityName -eq $vm.Name) {
                    $SnapUser = $Task.Reason.Username
                    break
                }
            }

            $results += [PSCustomObject]@{
                VMName = $vm.Name
                SnapshotName = $snapshot.Name
                Created = $snapshot.Created
                SizeGB = $sizeGB
                CreatedBy = $SnapUser
            }

            # Destroy the collector to free up resources
            $TaskCollector.DestroyCollector()
        }
    }
}

# Sort results by size (largest first) and display in table format
$results | Sort-Object -Property SizeGB -Descending | Format-Table -AutoSize

# Display total count of snapshots found
Write-Host "Total snapshots found (>2GB):" $results.Count -ForegroundColor Green

# Optionally, export sorted results to a CSV file
# $results | Sort-Object -Property SizeGB -Descending | Export-Csv -Path "C:\VMSnapshots_Filtered.csv" -NoTypeInformation

# Disconnect from the vCenter server
Disconnect-VIServer -Server * -Confirm:$false