# PowerShell script to enable the "Always prompt for password upon connection" RDP security policy

# Check if the script is running with Administrator privileges
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error "This script must be run with Administrator privileges. Please right-click the PowerShell icon and select 'Run as administrator'."
    exit 1
}

# Define the registry path and value for the policy
# This corresponds to:
# Computer Configuration -> Administrative Templates -> Windows Components -> Remote Desktop Services -> Remote Desktop Session Host -> Security -> "Always promptly for password upon connection"
$RegistryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
$ValueName = "fPromptForPassword"
$ValueData = 1 # Set to 1 to Enable the policy

Write-Host "Ensuring the registry key path exists: $RegistryPath"

try {
    # Create the registry key path if it doesn't exist.
    # -Force ensures parent keys are created if necessary.
    New-Item -Path $RegistryPath -Force -ErrorAction Stop | Out-Null
    Write-Host "Registry key path exists or was created."
}
catch {
    Write-Error "Failed to ensure registry key path exists: $($_.Exception.Message)"
    exit 1
}

Write-Host "Setting the registry value '$ValueName' to $ValueData (Enabled)..."

try {
    # Set the registry value for the policy.
    Set-ItemProperty -Path $RegistryPath -Name $ValueName -Value $ValueData -Force -ErrorAction Stop
    Write-Host "Registry value '$ValueName' set successfully."
    Write-Host "The 'Always prompt for password upon connection' RDP policy is now enabled."
}
catch {
    Write-Error "Failed to set registry value: $($_.Exception.Message)"
    exit 1
}

Write-Host "`nRegistry modification complete."
Write-Host "Policy changes applied via registry might require a restart of the 'Remote Desktop Service' or running 'gpupdate /force' to take effect immediately."
Write-Host "Alternatively, the change will take effect upon the next system restart or RDP service restart."

# Optional: Uncomment the line below if you want to force a Group Policy update immediately
# Write-Host "Running 'gpupdate /force'..."
gpupdate /force