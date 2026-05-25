# PowerShell script to load environment variables from a .env file into the current session.
# Supports both simple KEY=VALUE format and bash-style "export KEY=VALUE" files.
#
# Usage (run from repository root):
#   . scripts/load-env.ps1
#   Or specify a custom path:
#   . scripts/load-env.ps1 -Path terraform/proxmox/.env

param (
    [string]$Path = ".env"
)

if (-not (Test-Path $Path)) {
    Write-Warning "Environment file not found at: $Path"
    return
}

Write-Host "Loading environment variables from $Path..." -ForegroundColor Cyan

Get-Content $Path | ForEach-Object {
    $line = $_.Trim()
    
    # Skip comments and empty lines
    if ($line.StartsWith("#") -or [string]::IsNullOrWhiteSpace($line)) {
        return
    }
    
    # Strip optional bash "export " prefix if present
    if ($line.StartsWith("export ")) {
        $line = $line.Substring(7).Trim()
    }
    
    $parts = $line.Split('=', 2)
    if ($parts.Length -eq 2) {
        $name = $parts[0].Trim()
        $value = $parts[1].Trim()
        
        # Remove single or double quotes surrounding the value
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        
        # Set environment variable for the active PowerShell process
        [System.Environment]::SetEnvironmentVariable($name, $value, [System.EnvironmentVariableTarget]::Process)
        Write-Host "  Set: $name" -ForegroundColor Gray
    }
}

Write-Host "Environment loaded successfully!" -ForegroundColor Green
