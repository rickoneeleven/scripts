# --- Configuration ---
$targetUrl = "https://10.200.0.18/portal/webclient/icons-21068817/logo.png"
$timeoutSeconds = 10
$pauseBetweenAttemptsSeconds = 1 # How long to wait before the next attempt

# Headers to try and force a fresh download
$headers = @{
    "Pragma"        = "no-cache"
    "Cache-Control" = "no-cache, no-store, must-revalidate"
}

# --- WARNING: SSL/TLS Certificate Validation Bypass ---
Write-Warning "Disabling SSL/TLS certificate validation for this session. This is insecure and should only be used if you trust the server and network."

# Ensure the C# TypeDefinition is correct
$CallbackTypeDef = @"
using System;
using System.Net;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;
public class ServerCertificateValidationCallback
{
    public static void Initialize()
    {
        ServicePointManager.ServerCertificateValidationCallback =
            new RemoteCertificateValidationCallback(
                delegate (
                    object sender,
                    X509Certificate certificate,
                    X509Chain chain,
                    SslPolicyErrors sslPolicyErrors
                ) {
                    // Always accept the certificate
                    return true;
                }
            );
    }
}
"@

# Check if the type is already loaded. If not, add it.
if (-not ([System.Management.Automation.PSTypeName]'ServerCertificateValidationCallback').Type) {
    try {
        Add-Type -TypeDefinition $CallbackTypeDef -Language CSharp
        Write-Host "INFO: ServerCertificateValidationCallback type loaded." -ForegroundColor Cyan
    } catch {
        Write-Error "FATAL: Could not add ServerCertificateValidationCallback type. SSL Bypass will likely fail. Error: $($_.Exception.Message)"
    }
} else {
    Write-Host "INFO: ServerCertificateValidationCallback type was already loaded." -ForegroundColor Cyan
}

# Always try to initialize/re-initialize using the C# static method
$SslCallbackType = $null
try {
    # Attempt to get a reference to the type directly.
    # If Add-Type failed or the type doesn't exist, this will be caught.
    $SslCallbackType = [ServerCertificateValidationCallback]
}
catch {
    # This catch block handles cases where [ServerCertificateValidationCallback] itself causes an error
    Write-Verbose "Verbose: Could not directly reference [ServerCertificateValidationCallback]. Error: $($_.Exception.Message)"
}

if ($SslCallbackType -is [type] -and $SslCallbackType.FullName -eq 'ServerCertificateValidationCallback') {
    # The type exists and is what we expect
    try {
        [ServerCertificateValidationCallback]::Initialize()
        Write-Host "INFO: SSL/TLS certificate validation callback initialized/re-initialized via C# method." -ForegroundColor Cyan
    } catch {
        Write-Error "ERROR: Failed to initialize/re-initialize ServerCertificateValidationCallback via C# method. SSL Bypass may fail. Error: $($_.Exception.Message)"
    }
} else {
    Write-Warning "WARNING: ServerCertificateValidationCallback type is not available or not correctly defined. SSL bypass using C# method cannot be configured."
}
# --- End SSL Bypass ---


# --- Force newer TLS protocols ---
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls
    Write-Host "INFO: Attempted to set SecurityProtocol to Tls12, Tls11, Tls1.0." -ForegroundColor Cyan
}
catch {
    Write-Warning "WARNING: Could not set SecurityProtocol. This might be an issue on older systems/PowerShell versions. Error: $($_.Exception.Message)"
}
# --- End TLS Protocol Specification ---


Write-Host "Starting continuous download test for: $targetUrl"
Write-Host "Timeout set to: $timeoutSeconds seconds"
Write-Host "Press CTRL+C to stop."
Write-Host "--------------------------------------------------"

# --- Main Loop ---
while ($true) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host -NoNewline "[$timestamp] Attempting download... "

    try {
        # Measure the command execution time
        $measurement = Measure-Command {
            $response = Invoke-WebRequest -Uri $targetUrl -TimeoutSec $timeoutSeconds -Headers $headers -UseBasicParsing -DisableKeepAlive
        }

        $durationSeconds = $measurement.TotalSeconds
        Write-Host "SUCCESS! Loaded in $($durationSeconds.ToString("F3")) seconds. Status: $($response.StatusCode)" -ForegroundColor Green

    }
    catch [System.Net.WebException] {
        $exception = $_.Exception
        if ($exception.Status -eq [System.Net.WebExceptionStatus]::Timeout) {
            Write-Host "ERROR: Request timed out after $timeoutSeconds seconds." -ForegroundColor Red
        }
        # Check specifically for the TrustFailure due to SSL/TLS (though our bypass should prevent this specific type)
        elseif ($exception.InnerException -is [System.Security.Authentication.AuthenticationException] -and $exception.Status -eq [System.Net.WebExceptionStatus]::SecureChannelFailure) {
             Write-Host "ERROR: Failed to download. Status: $($exception.Status). Message: $($exception.InnerException.Message) (SSL/TLS trust issue, despite attempted bypass)." -ForegroundColor Red
        }
        else {
            $errorMessage = "ERROR: Failed to download. Status: $($exception.Status)"
            if ($exception.Response) {
                $errorMessage += ". HTTP Status Code: $([int]$exception.Response.StatusCode)"
            }
            $errorMessage += ". Message: $($exception.Message)"
            if ($exception.InnerException) { # Important to show the inner exception
                $errorMessage += " Inner Exception: $($exception.InnerException.GetType().FullName): $($exception.InnerException.Message)"
            }
            Write-Host $errorMessage -ForegroundColor Red
        }
    }
    catch {
        # Catch any other unexpected errors
        Write-Host "UNEXPECTED ERROR: $($_.Exception.Message)" -ForegroundColor DarkYellow
        if ($_.Exception.InnerException) {
             Write-Host "UNEXPECTED INNER ERROR: $($_.Exception.InnerException.Message)" -ForegroundColor DarkYellow
        }
    }

    # Pause before the next attempt
    Start-Sleep -Seconds $pauseBetweenAttemptsSeconds
}