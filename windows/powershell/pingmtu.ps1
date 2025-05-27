<#
.SYNOPSIS
    Diagnoses Path MTU issues to a target host.
.DESCRIPTION
    Uses .NET Ping class to accurately set the Don't Fragment bit for MTU testing.
    Attempts to identify the problematic hop if MTU is below standard.
.PARAMETER TargetIP
    The IP address or hostname of the target device.
.EXAMPLE
    .\PingMtu.ps1 -TargetIP 10.200.0.18
.NOTES
    Author: Your Name
    Date:   October 26, 2023
    Requires PowerShell 5.1 or later.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TargetIP
)

# --- Configuration ---
$InitialPingCount = 10
$InitialPingSuccessThreshold = 1 
$StandardEthernetPayload = 1472 # 1500 (MTU) - 20 (IP) - 8 (ICMP)
$MinPayloadSize = 36             # Smallest practical payload for ICMP (results in 64-byte IP packet)
$TracerouteMaxHops = 30
$DotNetPingTimeoutMs = 2000      # Timeout for individual .NET pings

# --- Helper Function ---
function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host "[$([datetime]::now.ToString('HH:mm:ss'))] $Message" -ForegroundColor $Color
}

# --- DF Ping Function using .NET ---
function Test-PingWithDf {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ComputerName,
        [Parameter(Mandatory=$true)]
        [int]$BufferSize,
        [int]$Timeout = $DotNetPingTimeoutMs 
    )

    $PingSender = New-Object System.Net.NetworkInformation.Ping
    $PingOptions = New-Object System.Net.NetworkInformation.PingOptions
    $PingOptions.DontFragment = $true

    if ($BufferSize -lt 0) { # Buffer size cannot be negative for byte array
        Write-Warning "BufferSize was negative, setting to 0 for Test-PingWithDf."
        $BufferSize = 0 
    }
    $DummyData = [byte[]]::new($BufferSize) 

    try {
        $Reply = $PingSender.Send($ComputerName, $Timeout, $DummyData, $PingOptions)
        
        switch ($Reply.Status) {
            ([System.Net.NetworkInformation.IPStatus]::Success) {
                return [pscustomobject]@{
                    StatusCode = 0 # Mimic Test-Connection success status
                    ResponseTime = $Reply.RoundtripTime
                    TimeToLive = if ($Reply.Options) { $Reply.Options.Ttl } else { 128 } # Default TTL if not in options
                    StatusString = 'Success'
                }
            }
            ([System.Net.NetworkInformation.IPStatus]::PacketTooBig) {
                Write-Verbose "PacketTooBig status received for $ComputerName with size $BufferSize via Test-PingWithDf"
                throw "PacketTooBig" # Specific exception for MTU logic
            }
            default { # Other failure statuses like Timeout, DestinationUnreachable etc.
                Write-Verbose "Ping failed for $ComputerName with size $BufferSize via Test-PingWithDf. Status: $($Reply.Status)"
                throw "PingFailed: $($Reply.Status)" # Generic ping failure
            }
        }
    }
    catch { # Catches exceptions from Send() method (e.g., host not found, invalid argument) or our re-thrown ones
        Write-Verbose "Exception in Test-PingWithDf to $ComputerName with size $BufferSize : $($_.Exception.Message)"
        throw # Re-throw to be handled by the main logic's try/catch
    }
    finally {
        if ($PingSender -is [System.IDisposable]) { 
            $PingSender.Dispose() 
        }
    }
}


# --- Phase 1: Basic Connectivity Check (using Test-Connection) ---
Write-Log "Phase 1: Basic Connectivity Check to $TargetIP..." -Color Cyan
$pingResults = @()
$successfulPings = 0
try {
    1..$InitialPingCount | ForEach-Object {
        $result = Test-Connection -ComputerName $TargetIP -Count 1 -ErrorAction SilentlyContinue
        $pingResults += $result
        if ($result -and $result.StatusCode -eq 0) {
            $successfulPings++
            Write-Log "Ping #$_ to $TargetIP successful (Time: $($result.ResponseTime)ms, TTL: $($result.TimeToLive))" -Color Green
        } else {
            Write-Log "Ping #$_ to $TargetIP failed or timed out." -Color Yellow
        }
        Start-Sleep -Milliseconds 100 
    }
}
catch {
    Write-Log "An error occurred during initial ping: $($_.Exception.Message)" -Color Red
}

if ($successfulPings -lt $InitialPingSuccessThreshold) {
    Write-Log "Initial connectivity test failed. Only $successfulPings out of $InitialPingCount pings succeeded." -Color Red
    Write-Log "Please check route, ICMP on target, and firewalls." -Color Red
    exit 1
}
Write-Log "Initial connectivity established ($successfulPings / $InitialPingCount successful)." -Color Green

# --- Phase 2: Find Max Successful ICMP Payload (Path MTU Discovery using .NET Ping) ---
Write-Log "Phase 2: Discovering Path MTU to $TargetIP (using .NET Ping with DF bit)..." -Color Cyan

$low = $MinPayloadSize
$high = $StandardEthernetPayload 
$lastSuccessfulPayload = 0
$firstFailingPayload = $StandardEthernetPayload + 1 

Write-Log "Searching for max ICMP payload between $low and $high bytes..."

while ($low -le $high) {
    $currentPayload = [Math]::Floor(($low + $high) / 2)
    # Ensure currentPayload doesn't go below MinPayloadSize in the binary search logic
    if ($currentPayload -lt $MinPayloadSize) { 
        $currentPayload = $MinPayloadSize
        # If $currentPayload is already $MinPayloadSize and it's the first viable test in a squeezed range
        if ($low -gt $high -and $lastSuccessfulPayload -eq 0) { 
            Write-Log "Testing payload: $currentPayload bytes (min boundary)..." -Color Gray
            try {
                $result = Test-PingWithDf -ComputerName $TargetIP -BufferSize $currentPayload
                $lastSuccessfulPayload = $currentPayload # Min payload worked
            } catch {
                 $firstFailingPayload = [Math]::Min($firstFailingPayload, $currentPayload) # Min payload failed
            }
            break # Exit loop as min payload defines the boundary or failure
        }
         if ($low -gt $high) {break} # Standard binary search exit condition
    }

    Write-Log "Testing payload: $currentPayload bytes..." -Color Gray
    try {
        $result = Test-PingWithDf -ComputerName $TargetIP -BufferSize $currentPayload
        $lastSuccessfulPayload = $currentPayload
        $low = $currentPayload + 1 
    }
    catch { # Catches "PacketTooBig" or "PingFailed:Status" from Test-PingWithDf
        $firstFailingPayload = [Math]::Min($firstFailingPayload, $currentPayload) 
        $high = $currentPayload - 1 
    }
    Start-Sleep -Milliseconds 100 
}

$pathMTU = $lastSuccessfulPayload + 28 # ICMP Payload + IP Header (20) + ICMP Header (8)

Write-Log "-----------------------------------------------------" -Color Magenta
if ($lastSuccessfulPayload -gt 0) {
    Write-Log "Largest successful ICMP payload: $lastSuccessfulPayload bytes." -Color Green
    Write-Log "Path MTU to $TargetIP estimated at: $pathMTU bytes." -Color Green
    # Refine firstFailingPayload if binary search overshot
    if (($lastSuccessfulPayload + 1) -lt $firstFailingPayload) { 
        $firstFailingPayload = $lastSuccessfulPayload + 1
    }
     Write-Log "Pings with payload $($firstFailingPayload) bytes (IP Packet: $($firstFailingPayload + 28)) or larger are expected to fail with DF bit." -Color Yellow
} else {
    Write-Log "Could not determine a successful payload size with DF bit. Smallest tested pings failed." -Color Red
    Write-Log "This could indicate an issue with DF-set packets (e.g., blocked ICMP 'PacketTooBig' responses, device dropping all DF packets), or very low MTU." -Color Red
    exit 1
}
Write-Log "-----------------------------------------------------" -Color Magenta

if ($pathMTU -ge ($StandardEthernetPayload + 28) ) { 
    Write-Log "Path MTU appears to be standard ($pathMTU bytes). No further hop-by-hop MTU testing needed for this path." -Color Green
    exit 0
}

# --- Phase 3: Identify Problematic Hop ---
Write-Log "Phase 3: Path MTU ($pathMTU) is less than standard. Identifying problematic hop..." -Color Cyan
Write-Log "Will test hops with payload size: $firstFailingPayload bytes (IP Packet: $($firstFailingPayload + 28))"

$traceRouteResults = $null
try {
    Write-Log "Performing traceroute to $TargetIP (max $TracerouteMaxHops hops)..."
    # DEBUGGING Test-NetConnection: Removed -InformationLevel Quiet, Kept -ErrorAction Stop
    Write-Log "DEBUG: Running Test-NetConnection -TraceRoute with -ErrorAction Stop but WITHOUT -InformationLevel Quiet" -Color Yellow
    $traceRouteResults = Test-NetConnection -ComputerName $TargetIP -TraceRoute -Hops $TracerouteMaxHops -ErrorAction Stop
    Write-Log "DEBUG: Test-NetConnection -TraceRoute completed. Result object:" -Color Yellow
    $traceRouteResults | Format-List * -Force 
    Write-Log "DEBUG: TraceRoute property (actual hops):" -Color Yellow
    $traceRouteResults.TraceRoute | Format-Table -AutoSize 
}
catch {
    Write-Log "Traceroute failed during execution: $($_.Exception.Message)" -Color Red
    exit 1
}

if (-not $traceRouteResults -or -not $traceRouteResults.TraceRoute -or $traceRouteResults.TraceRoute.Count -eq 0) { 
    Write-Log "Traceroute did not return usable hop information." -Color Red
    Write-Log "Please check the DEBUG output above. Manual traceroute might be needed." -Color Red
    exit 1
}

$hopsToTest = $traceRouteResults.TraceRoute 

if (-not $hopsToTest -or $hopsToTest.Count -eq 0) { # Secondary check, should be covered by above
     Write-Log "Could not extract hop IP addresses from traceroute results (secondary check failed)." -Color Red
     exit 1
}

$previousHopRespondedToFailingSize = $true 
$problemHopIP = $null
$identifiedProblem = $false

Write-Log "Testing each hop with ICMP payload $firstFailingPayload bytes (DF bit set)..."
for ($i = 0; $i -lt $hopsToTest.Count; $i++) {
    $currentHopIP = $hopsToTest[$i] # Already a string from .TraceRoute
    if (-not $currentHopIP -or $currentHopIP -eq "0.0.0.0" -or $currentHopIP -match "Request timed out" -or $currentHopIP -match "General failure" -or $currentHopIP -eq "*") {
        Write-Log "Hop $($i+1): '$($currentHopIP)' appears non-responsive or invalid. Skipping." -Color Gray
        $previousHopRespondedToFailingSize = $false 
        continue
    }

    Write-Log "Testing Hop $($i+1): $currentHopIP with payload $firstFailingPayload..." -Color Yellow
    $hopPingSuccess = $false
    try {
        $hopResult = Test-PingWithDf -ComputerName $currentHopIP -BufferSize $firstFailingPayload
        Write-Log "  Hop $currentHopIP RESPONDED to payload $firstFailingPayload. (Time: $($hopResult.ResponseTime)ms)" -Color Green
        $hopPingSuccess = $true
    }
    catch { # Catches "PacketTooBig" or "PingFailed:Status" from Test-PingWithDf
        Write-Log "  Hop $currentHopIP FAILED for payload $firstFailingPayload. Error: ($($_.Exception.Message.Split('`n')[0]))" -Color Red # Get first line of error
        $hopPingSuccess = $false
    }

    if (-not $hopPingSuccess) {
        $problemHopIP = $currentHopIP
        $identifiedProblem = $true
        if ($previousHopRespondedToFailingSize) {
            $previousHopDisplay = "N/A (first hop, or previous was non-responsive)"
            if ($i -gt 0 -and $hopsToTest[$i-1]) { 
                $previousHopDisplay = $hopsToTest[$i-1] # Previous hop IP string
            }
            Write-Log "MTU Issue likely: Packets of size $($firstFailingPayload + 28) dropped by/before $problemHopIP. Prev hop ($previousHopDisplay) was OK or skipped." -Color Red
        } else {
            Write-Log "MTU Issue likely: Packets of size $($firstFailingPayload + 28) dropped AT or BEFORE $problemHopIP. Prev hop also failed/untestable with this size." -Color Red
        }
        break 
    }
    $previousHopRespondedToFailingSize = $hopPingSuccess 
    Start-Sleep -Milliseconds 100
}

# After loop, if no problem hop identified but MTU is low, target the destination
if (-not $identifiedProblem -and (($lastSuccessfulPayload + 1) -lt $firstFailingPayload) ) { 
    Write-Log "All testable intermediate hops responded to payload $firstFailingPayload." -Color Yellow
    Write-Log "The MTU issue likely lies with the final destination $TargetIP itself or its direct segment/firewall." -Color Yellow
    $problemHopIP = $TargetIP 
    $identifiedProblem = $true
} elseif (-not $identifiedProblem -and ($pathMTU -lt ($StandardEthernetPayload + 28))) { # If MTU is low but no specific hop found
    Write-Log "Could not definitively identify a problematic intermediate hop. Defaulting to testing against target $TargetIP if its MTU is low." -Color Yellow
    $problemHopIP = $TargetIP
    $identifiedProblem = $true
}


# --- Phase 4: Continuous Ping on Problematic Hop / Target ---
if ($identifiedProblem -and $problemHopIP) {
    Write-Log "Phase 4: Continuously pinging ${problemHopIP} with failing payload $firstFailingPayload (DF bit set)..." -Color Cyan 
    Write-Log "Press CTRL+C to stop." -Color Cyan
    Write-Log "If this hop starts replying consistently, the MTU issue at this point might be resolved." -Color Cyan
    Write-Log "You may then need to re-run the script to verify the full path MTU to the original target $TargetIP." -Color Cyan

    $consecutiveSuccesses = 0
    $consecutiveFailures = 0
    $thresholdForResolution = 5 

    try {
        while ($true) {
            try {
                $loopResult = Test-PingWithDf -ComputerName $problemHopIP -BufferSize $firstFailingPayload
                Write-Log "REPLY from ${problemHopIP}: bytes=$firstFailingPayload time=$($loopResult.ResponseTime)ms TTL=$($loopResult.TimeToLive)" -Color Green 
                $consecutiveSuccesses++
                $consecutiveFailures = 0
                if ($consecutiveSuccesses -ge $thresholdForResolution) {
                    Write-Log "Hop ${problemHopIP} responding consistently to payload $firstFailingPayload. Issue might be resolved at this hop." -Color Green 
                    break 
                }
            } catch { # Catches exceptions from Test-PingWithDf
                Write-Log "Request timed out or failed for ${problemHopIP} with payload $firstFailingPayload. Error: ($($_.Exception.Message.Split('`n')[0]))" -Color Yellow 
                $consecutiveFailures++
                $consecutiveSuccesses = 0
            }
            Start-Sleep -Seconds 1
        }
    }
    catch [System.Management.Automation.PipelineStoppedException] {
        Write-Log "Script stopped by user (CTRL+C)." -Color Cyan
    }
    catch { # Catch any other unexpected error in the while loop setup
        Write-Log "An error occurred setting up continuous ping: $($_.Exception.Message)" -Color Red
    }
} else {
    Write-Log "No specific problematic hop identified for continuous ping, or PMTU was standard." -Color Yellow
}

Write-Log "Script finished." -Color Cyan