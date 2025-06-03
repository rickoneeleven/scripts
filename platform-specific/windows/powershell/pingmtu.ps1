<#
.SYNOPSIS
    Diagnoses Path MTU issues to a target host, including support for jumbo frame testing.
.DESCRIPTION
    Uses .NET Ping class to accurately set the Don't Fragment bit for MTU testing.
    Searches for the maximum Path MTU up to a configurable limit (MaxPayloadToSearch).
    Attempts to identify the problematic hop if MTU is below standard or the desired maximum.
.PARAMETER TargetIP
    The IP address or hostname of the target device. (Positional)
.PARAMETER MaxPayloadToSearch
    The maximum ICMP payload size the script should attempt to test.
    Default is 8972 (for a 9000-byte Path MTU: 8972 payload + 20 IP + 8 ICMP).
    Set lower (e.g., 1472) to only test up to standard Ethernet MTU.
.EXAMPLE
    .\PingMtu.ps1 10.200.0.18
.EXAMPLE
    .\PingMtu.ps1 example.com -MaxPayloadToSearch 4000
.NOTES
    Author: Your Name
    Date:   October 27, 2023
    Requires PowerShell 5.1 or later. (Note: Test-NetConnection parameter support varies by PS version)
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TargetIP,

    [Parameter(Mandatory = $false)]
    [int]$MaxPayloadToSearch = 8972 
)

# --- Configuration ---
$InitialPingCount = 10
$InitialPingSuccessThreshold = 1
$StandardEthernetPayload = 1472 
$MinPayloadSize = 36             
$TracerouteMaxHops = 30
$DotNetPingTimeoutMs = 2000      

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
    if ($BufferSize -lt 0) { $BufferSize = 0 }
    $DummyData = [byte[]]::new($BufferSize)

    try {
        $Reply = $PingSender.Send($ComputerName, $Timeout, $DummyData, $PingOptions)
        
        switch ($Reply.Status) {
            ([System.Net.NetworkInformation.IPStatus]::Success) {
                return [pscustomobject]@{
                    StatusCode = 0 
                    ResponseTime = $Reply.RoundtripTime
                    TimeToLive = if ($Reply.Options) { $Reply.Options.Ttl } else { 128 } 
                    StatusString = 'Success'
                }
            }
            ([System.Net.NetworkInformation.IPStatus]::PacketTooBig) {
                Write-Verbose "PacketTooBig status received for $ComputerName with size $BufferSize via Test-PingWithDf"
                throw "PacketTooBig" 
            }
            default { 
                Write-Verbose "Ping failed for $ComputerName with size $BufferSize via Test-PingWithDf. Status: $($Reply.Status)"
                throw "PingFailed: $($Reply.Status)" 
            }
        }
    }
    catch { 
        Write-Verbose "Exception in Test-PingWithDf to $ComputerName with size $BufferSize : $($_.Exception.Message)"
        throw 
    }
    finally {
        if ($PingSender -is [System.IDisposable]) { 
            $PingSender.Dispose() 
        }
    }
}

# --- Phase 1: Basic Connectivity Check ---
Write-Log "Phase 1: Basic Connectivity Check to $TargetIP..." -Color Cyan
$successfulPings = 0
try {
    1..$InitialPingCount | ForEach-Object {
        $result = Test-Connection -ComputerName $TargetIP -Count 1 -ErrorAction SilentlyContinue
        if ($result -and $result.StatusCode -eq 0) { $successfulPings++; Write-Log "Ping #$_ to $TargetIP successful (Time: $($result.ResponseTime)ms, TTL: $($result.TimeToLive))" -Color Green }
        else { Write-Log "Ping #$_ to $TargetIP failed or timed out." -Color Yellow }
        Start-Sleep -Milliseconds 100
    }
} catch { Write-Log "An error occurred during initial ping: $($_.Exception.Message)" -Color Red }

if ($successfulPings -lt $InitialPingSuccessThreshold) {
    Write-Log "Initial connectivity test failed. Only $successfulPings out of $InitialPingCount pings succeeded to ${TargetIP}." -Color Red; exit 1
}
Write-Log "Initial connectivity established ($successfulPings / $InitialPingCount successful to ${TargetIP})." -Color Green

# --- Phase 2: Discover Path MTU to Target (up to MaxPayloadToSearch) ---
Write-Log "Phase 2: Discovering Path MTU to $TargetIP (testing ICMP payloads from $MinPayloadSize up to $MaxPayloadToSearch bytes)..." -Color Cyan

$low = $MinPayloadSize
$high = $MaxPayloadToSearch
$binarySearchLastSuccessfulPayload = 0
$binarySearchFirstFailingPayload = $MaxPayloadToSearch + 100 

while ($low -le $high) {
    $currentPayload = [Math]::Floor(($low + $high) / 2)
    if ($currentPayload -lt $MinPayloadSize) { $currentPayload = $MinPayloadSize } 

    Write-Log "Testing payload (binary search to ${TargetIP}): $currentPayload bytes..." -Color Gray
    try {
        $null = Test-PingWithDf -ComputerName $TargetIP -BufferSize $currentPayload 
        $binarySearchLastSuccessfulPayload = $currentPayload
        $low = $currentPayload + 1
    } catch {
        $binarySearchFirstFailingPayload = [Math]::Min($binarySearchFirstFailingPayload, $currentPayload)
        $high = $currentPayload - 1
    }
    if ($low -gt $high -and $currentPayload -eq $MinPayloadSize -and $binarySearchLastSuccessfulPayload -eq 0 -and $binarySearchFirstFailingPayload -eq ($MaxPayloadToSearch + 100)) {
        if ($high -lt $MinPayloadSize) { $binarySearchFirstFailingPayload = $MinPayloadSize; }
        break;
    }
    Start-Sleep -Milliseconds 100
}

$lastSuccessfulPayloadToTarget = 0
$firstFailingPayloadToTarget = 0
$pathMtuToTarget = 0

Write-Log "-----------------------------------------------------" -Color Magenta
if ($binarySearchLastSuccessfulPayload -gt 0) {
    Write-Log "Binary search (up to $MaxPayloadToSearch bytes to ${TargetIP}) found largest successful payload: $binarySearchLastSuccessfulPayload bytes." -Color DarkGray

    $payloadToConfirmFailure = $binarySearchLastSuccessfulPayload + 1
    Write-Log "Verifying exact failure point: testing payload $payloadToConfirmFailure bytes to ${TargetIP}..." -Color Gray
    try {
        $null = Test-PingWithDf -ComputerName $TargetIP -BufferSize $payloadToConfirmFailure 
        $lastSuccessfulPayloadToTarget = $payloadToConfirmFailure
        $pathMtuToTarget = $lastSuccessfulPayloadToTarget + 28
        $firstFailingPayloadToTarget = $lastSuccessfulPayloadToTarget + 1 

        Write-Log "VERIFICATION: Payload $payloadToConfirmFailure bytes SUCCEEDED to ${TargetIP}." -Color Green
        Write-Log "Path MTU to ${TargetIP} is at least $pathMtuToTarget bytes." -Color Green
        if ($lastSuccessfulPayloadToTarget -ge $MaxPayloadToSearch) {
            Write-Log "This meets or exceeds the configured MaxPayloadToSearch ($MaxPayloadToSearch bytes)." -Color Green
        }
        Write-Log "To find the absolute MTU limit if it's even higher, MaxPayloadToSearch would need to be increased." -Color Yellow
    } catch { 
        $lastSuccessfulPayloadToTarget = $binarySearchLastSuccessfulPayload 
        $firstFailingPayloadToTarget = $payloadToConfirmFailure
        $pathMtuToTarget = $lastSuccessfulPayloadToTarget + 28
        $errorMessage = $_.Exception.Message -replace "[\r\n]"," "
        Write-Log "VERIFICATION: Payload $payloadToConfirmFailure bytes FAILED to ${TargetIP} ($errorMessage)." -Color Yellow
        Write-Log "Final result: Largest successful ICMP payload to ${TargetIP}: $lastSuccessfulPayloadToTarget bytes." -Color Green
        Write-Log "Path MTU to ${TargetIP} confirmed at: $pathMtuToTarget bytes." -Color Green
        Write-Log "Pings with payload $($firstFailingPayloadToTarget) bytes (IP Packet: $($firstFailingPayloadToTarget + 28)) or larger to ${TargetIP} WILL fail with DF bit." -Color Yellow
    }
} else { 
    $firstFailingPayloadToTarget = $binarySearchFirstFailingPayload 
    if ($firstFailingPayloadToTarget -gt $MaxPayloadToSearch) {$firstFailingPayloadToTarget = $MinPayloadSize} 
    Write-Log "Could not determine any successful payload size with DF bit to ${TargetIP} (tested from $MinPayloadSize up to $MaxPayloadToSearch bytes)." -Color Red
    Write-Log "Smallest tested pings (e.g., payload $firstFailingPayloadToTarget to ${TargetIP}) failed. Check basic DF packet handling or severe MTU restriction." -Color Red
    exit 1
}
Write-Log "-----------------------------------------------------" -Color Magenta

$performPhase3 = $true
if ($pathMtuToTarget -ge ($MaxPayloadToSearch + 28)) {
    Write-Log "Path MTU ($pathMtuToTarget bytes to ${TargetIP}) meets or exceeds the maximum configured test payload's MTU ($($MaxPayloadToSearch + 28) bytes)." -Color Green
    Write-Log "Jumbo frames (up to this size: $pathMtuToTarget bytes) appear to be working end-to-end to ${TargetIP}." -Color Green
    $performPhase3 = $false
} elseif ($pathMtuToTarget -ge ($StandardEthernetPayload + 28)) {
    Write-Log "Path MTU to ${TargetIP} is $pathMtuToTarget bytes." -Color Yellow
    Write-Log "This is standard or partial jumbo, but less than your configured maximum test MTU of $($MaxPayloadToSearch + 28) bytes." -Color Yellow
    Write-Log "Phase 3 will investigate intermediate hops using payload $firstFailingPayloadToTarget bytes (IP Packet: $($firstFailingPayloadToTarget + 28)) to identify the restriction point for ${TargetIP}." -Color Cyan
} else { 
    Write-Log "Path MTU to ${TargetIP} ($pathMtuToTarget bytes) is less than standard Ethernet MTU ($($StandardEthernetPayload + 28) bytes)." -Color Red
    Write-Log "Phase 3 will identify the problematic hop using payload $firstFailingPayloadToTarget bytes (IP Packet: $($firstFailingPayloadToTarget + 28)) for path to ${TargetIP}." -Color Cyan
}

if (-not $performPhase3) {
    Write-Log "Script finished." -Color Cyan
    exit 0
}

# --- Phase 3: Identify Problematic Hop ---
$traceRouteResults = $null
$tncError = $null # For -ErrorVariable

try {
    Write-Log "Performing traceroute to $TargetIP (max $TracerouteMaxHops hops)..."
    $traceRouteResults = Test-NetConnection -ComputerName $TargetIP -TraceRoute -Hops $TracerouteMaxHops -ErrorAction Stop `
        -ErrorVariable tncError 

    # If TNC itself threw a terminating error, script goes to CATCH.
    # If TNC ran but $traceRouteResults.TraceRoute is bad, this DEBUG block will execute.
    if (-not ($traceRouteResults -and $traceRouteResults.TraceRoute -and $traceRouteResults.TraceRoute.Count -gt 0)) {
        Write-Log "DEBUG: traceRouteResults.TraceRoute is null, empty, TraceRoute property is missing, or traceRouteResults itself is null." -Color Magenta
        Write-Log "DEBUG: traceRouteResults object: $($traceRouteResults | Format-List * -Force | Out-String)" -Color Magenta
        if ($traceRouteResults -and $traceRouteResults.PSObject.Properties["TraceRoute"]) { # Check if property exists before getting type
             Write-Log "DEBUG: Type of TraceRoute property: $($traceRouteResults.TraceRoute.GetType().FullName)" -Color Magenta
        } else {
             Write-Log "DEBUG: TraceRoute property does not exist on traceRouteResults object or traceRouteResults is null." -Color Magenta
        }
        if ($tncError) { 
            Write-Log "DEBUG: tncError (-ErrorVariable content): $($tncError.ErrorRecord | Out-String)" -Color Red
        }
        if ($Error[0]) { 
            Write-Log "DEBUG: PowerShell `$Error[0]: $($Error[0].ErrorRecord | Out-String)" -Color Red 
            Write-Log "DEBUG: PowerShell `$Error[0] Exception: $($Error[0].Exception.ToString())" -Color Red
        }
    }

} catch {
    Write-Log "Traceroute command execution failed for ${TargetIP}: $($_.Exception.Message)" -Color Red 
    if ($tncError) { 
        Write-Log "DEBUG: tncError from -ErrorVariable in CATCH block: $($tncError.ErrorRecord | Out-String)" -Color Red
    }
    Write-Log "DEBUG: traceRouteResults in CATCH block: $($traceRouteResults | Format-List * -Force | Out-String)" -Color Magenta
    exit 1
}

# Check after try-catch if TraceRoute property is usable
if (-not ($traceRouteResults -and $traceRouteResults.TraceRoute -and $traceRouteResults.TraceRoute.Count -gt 0)) {
    Write-Log "Traceroute for ${TargetIP} did not return usable hop information. Review DEBUG logs if any were printed above." -Color Red
    exit 1
}
# At this point, $traceRouteResults.TraceRoute should be a non-empty array/collection.

$hopsToTest = $traceRouteResults.TraceRoute
$problemHopIP = $null
$identifiedProblem = $false
$previousHopRespondedToFailingSizeTest = $true 

Write-Log "Testing each hop with ICMP payload $firstFailingPayloadToTarget bytes (IP Packet: $($firstFailingPayloadToTarget + 28)). This payload failed end-to-end to ${TargetIP}."
for ($i = 0; $i -lt $hopsToTest.Count; $i++) {
    $currentHopIP = $hopsToTest[$i] 
    if (-not $currentHopIP -is [string] -or [string]::IsNullOrWhiteSpace($currentHopIP) -or $currentHopIP -match "^\*|0\.0\.0\.0|Request timed out|General failure") {
        Write-Log "Hop $($i+1) ('$($currentHopIP)') on path to ${TargetIP} non-responsive/invalid type. Skipping." -Color Gray
        $previousHopRespondedToFailingSizeTest = $false 
        continue
    }

    Write-Log "Testing Hop $($i+1): $currentHopIP (on path to ${TargetIP}) with payload $firstFailingPayloadToTarget..." -Color Yellow
    $hopPingSuccess = $false
    try {
        $null = Test-PingWithDf -ComputerName $currentHopIP -BufferSize $firstFailingPayloadToTarget 
        Write-Log "  Hop $currentHopIP RESPONDED to payload $firstFailingPayloadToTarget." -Color Green
        $hopPingSuccess = $true
    } catch {
        $errorMessage = $_.Exception.Message -replace "[\r\n]"," "
        Write-Log "  Hop $currentHopIP FAILED for payload $firstFailingPayloadToTarget. Error: ($errorMessage)" -Color Red
        $problemHopIP = $currentHopIP
        $identifiedProblem = $true
        $previousHopDisplay = "N/A (first hop, or previous untestable)"
        if ($i -gt 0) {
            for ($j = $i -1; $j -ge 0; $j--) {
                if ($hopsToTest[$j] -and $hopsToTest[$j] -is [string] -and -not([string]::IsNullOrWhiteSpace($hopsToTest[$j])) -and $hopsToTest[$j] -notmatch "^\*|0\.0\.0\.0|Request timed out|General failure") {
                    $previousHopDisplay = $hopsToTest[$j]; break
                }
                if ($j -eq 0) { $previousHopDisplay = "Source (or all previous untestable)"; }
            }
        }

        if ($pathMtuToTarget -lt ($StandardEthernetPayload + 28)) { 
             Write-Log "SUB-STANDARD MTU Issue for path to ${TargetIP}: Packets of size $($firstFailingPayloadToTarget + 28) dropped by/before $problemHopIP. Prev hop ($previousHopDisplay) was OK or skipped." -Color Red
        } else { 
            Write-Log "JUMBO FRAME LIMITATION for path to ${TargetIP}: While Path MTU to ${TargetIP} is $pathMtuToTarget bytes, hop $problemHopIP also failed payload $firstFailingPayloadToTarget." -Color Red
            Write-Log "  This hop ($problemHopIP) is where frames of size $($firstFailingPayloadToTarget + 28) (payload $firstFailingPayloadToTarget) start failing along the path to ${TargetIP}." -Color Red
            Write-Log "  To achieve larger frames (up to $pathMtuToTarget or desired $($MaxPayloadToSearch + 28)) towards ${TargetIP}, investigate $problemHopIP." -Color Red
        }
        break 
    }
    $previousHopRespondedToFailingSizeTest = $hopPingSuccess
    Start-Sleep -Milliseconds 100
}

if (-not $identifiedProblem) { 
    $problemHopIP = $TargetIP 
    $identifiedProblem = $true 
    if ($pathMtuToTarget -lt ($StandardEthernetPayload + 28)) {
        Write-Log "All testable intermediate hops on path to ${TargetIP} passed payload $firstFailingPayloadToTarget." -Color Yellow
        Write-Log "The sub-standard MTU issue ($pathMtuToTarget bytes for ${TargetIP}) likely lies with the final destination ${TargetIP} or its direct segment/firewall." -Color Red
    } elseif ($pathMtuToTarget -lt ($MaxPayloadToSearch + 28)) { 
        Write-Log "All testable intermediate hops on path to ${TargetIP} passed payload $firstFailingPayloadToTarget." -Color Yellow
        Write-Log "The MTU limit of $pathMtuToTarget bytes for ${TargetIP} (less than desired $($MaxPayloadToSearch + 28)) appears to be at the target ${TargetIP} or its direct link/firewall." -Color Yellow
        Write-Log "To achieve jumbo frames larger than $pathMtuToTarget (up to $($MaxPayloadToSearch + 28) bytes) to ${TargetIP}, investigate ${TargetIP}." -Color Yellow
    } else {
         Write-Log "All intermediate hops passed. Path MTU to ${TargetIP} ($pathMtuToTarget) meets/exceeds MaxPayloadToSearch. No problem found." -Color Green
         $identifiedProblem = $false 
    }
}

# --- Phase 4: Continuous Ping on Problematic Hop / Target ---
if ($identifiedProblem -and $problemHopIP) {
    Write-Log "Phase 4: Continuously pinging ${problemHopIP} with payload $firstFailingPayloadToTarget (IP Packet: $($firstFailingPayloadToTarget+28), DF bit set)..." -Color Cyan
    Write-Log "This payload was identified as failing towards/at this hop (or the target ${TargetIP})." -Color Cyan
    Write-Log "Press CTRL+C to stop." -Color Cyan
    $consecutiveSuccesses = 0; $thresholdForResolution = 5
    try {
        while ($true) {
            try {
                $loopResult = Test-PingWithDf -ComputerName $problemHopIP -BufferSize $firstFailingPayloadToTarget 
                Write-Log "REPLY from ${problemHopIP}: payload=$firstFailingPayloadToTarget time=$($loopResult.ResponseTime)ms TTL=$($loopResult.TimeToLive)" -Color Green
                $consecutiveSuccesses++; if ($consecutiveSuccesses -ge $thresholdForResolution) { Write-Log "Hop ${problemHopIP} responding consistently. Issue might be resolved at this hop for this size." -Color Green; break }
            } catch {
                $errorMessage = $_.Exception.Message -replace "[\r\n]"," "
                Write-Log "Request timed out/failed for ${problemHopIP} with payload $firstFailingPayloadToTarget. Error: ($errorMessage)" -Color Yellow
                $consecutiveSuccesses = 0
            }
            Start-Sleep -Seconds 1
        }
    } catch [System.Management.Automation.PipelineStoppedException] { Write-Log "Script stopped by user." -Color Cyan }
      catch { Write-Log "Error in continuous ping to ${problemHopIP}: $($_.Exception.Message)" -Color Red }
} else {
    Write-Log "No specific problematic hop identified for continuous ping, or PMTU to ${TargetIP} was as expected." -Color Yellow
}
Write-Log "Script finished." -Color Cyan