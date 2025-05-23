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
# This code will bypass SSL certificate validation for the current PowerShell session.
# Use with extreme caution and only if you trust the server and network.
Write-Warning "Disabling SSL/TLS certificate validation for this session. This is insecure and should only be used if you trust the server and network."
if (-not ([System.Management.Automation.PSTypeName]'ServerCertificateValidationCallback').Type) {
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
    Add-Type -TypeDefinition $CallbackTypeDef -Language CSharp
    [ServerCertificateValidationCallback]::Initialize()
} else {
    # If already defined (e.g., from a previous run in the same ISE session), re-initialize to be sure.
    # This part might be redundant if the type is already loaded and callback set,
    # but ensures it's active if a previous script might have reset it to null.
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {
        param($sender, $certificate, $chain, $sslPolicyErrors)
        # $true means "trust the certificate" regardless of errors
        return $true
    }
}
# --- End SSL Bypass ---


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
        # Check specifically for the TrustFailure due to SSL/TLS
        elseif ($exception.InnerException -is [System.Security.Authentication.AuthenticationException] -and $exception.Status -eq [System.Net.WebExceptionStatus]::SecureChannelFailure) {
             Write-Host "ERROR: Failed to download. Status: $($exception.Status). Message: $($exception.InnerException.Message) (SSL/TLS trust issue, attempted bypass)." -ForegroundColor Red
        }
        else {
            $errorMessage = "ERROR: Failed to download. Status: $($exception.Status)"
            if ($exception.Response) {
                $errorMessage += ". HTTP Status Code: $([int]$exception.Response.StatusCode)"
            }
            $errorMessage += ". Message: $($exception.Message)"
            Write-Host $errorMessage -ForegroundColor Red
        }
    }
    catch {
        # Catch any other unexpected errors
        Write-Host "UNEXPECTED ERROR: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    # Pause before the next attempt
    Start-Sleep -Seconds $pauseBetweenAttemptsSeconds
}
$timeoutSeconds = 10
$pauseBetweenAttemptsSeconds = 1 # How long to wait before the next attempt

# Headers to try and force a fresh download
$headers = @{
    "Pragma"        = "no-cache"
    "Cache-Control" = "no-cache, no-store, must-revalidate"
}

# --- WARNING: SSL/TLS Certificate Validation Bypass ---
# This code will bypass SSL certificate validation for the current PowerShell session.
# Use with extreme caution and only if you trust the server and network.
Write-Warning "Disabling SSL/TLS certificate validation for this session. This is insecure and should only be used if you trust the server and network."
if (-not ([System.Management.Automation.PSTypeName]'ServerCertificateValidationCallback').Type) {
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
                        X509Chain chain,a
                        SslPolicyErrors sslPolicyErrors
                    ) {
                        // Always accept the certificate
                        return true;
                    }
                );
        }
    }
"@
    Add-Type -TypeDefinition $CallbackTypeDef -Language CSharp
    [ServerCertificateValidationCallback]::Initialize()
} else {
    # If already defined (e.g., from a previous run in the same ISE session), re-initialize to be sure.
    # This part might be redundant if the type is already loaded and callback set,
    # but ensures it's active if a previous script might have reset it to null.
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {
        param($sender, $certificate, $chain, $sslPolicyErrors)
        # $true means "trust the certificate" regardless of errors
        return $true
    }
}
# --- End SSL Bypass ---


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
        # Check specifically for the TrustFailure due to SSL/TLS
        elseif ($exception.InnerException -is [System.Security.Authentication.AuthenticationException] -and $exception.Status -eq [System.Net.WebExceptionStatus]::SecureChannelFailure) {
             Write-Host "ERROR: Failed to download. Status: $($exception.Status). Message: $($exception.InnerException.Message) (SSL/TLS trust issue, attempted bypass)." -ForegroundColor Red
        }
        else {
            $errorMessage = "ERROR: Failed to download. Status: $($exception.Status)"
            if ($exception.Response) {
                $errorMessage += ". HTTP Status Code: $([int]$exception.Response.StatusCode)"
            }
            $errorMessage += ". Message: $($exception.Message)"
            Write-Host $errorMessage -ForegroundColor Red
        }
    }
    catch {
        # Catch any other unexpected errors
        Write-Host "UNEXPECTED ERROR: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    # Pause before the next attempt
    Start-Sleep -Seconds $pauseBetweenAttemptsSeconds
}