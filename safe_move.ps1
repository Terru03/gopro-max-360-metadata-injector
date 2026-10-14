# ==============================================================================
# Safe Watch Folder Mover
# Moves files from Staging to Watch Folder only when they are fully written.
# ==============================================================================
param(
    [string]$SourceDir = "P:\GoPro MAX 2\4 - GoPro Player Exports",
    [string]$DestDir = "P:\GoPro MAX 2\5 - Premiere Watch Folder"
)

# .NET file operations use the process cwd, which can differ from Set-Location.
# Resolve both paths through PowerShell before passing them to .NET.
$SourceDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SourceDir)
$DestDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestDir)

# Create directories if they don't exist
if (!(Test-Path -LiteralPath $SourceDir)) { New-Item -ItemType Directory -Force -Path $SourceDir | Out-Null }
if (!(Test-Path -LiteralPath $DestDir)) { New-Item -ItemType Directory -Force -Path $DestDir | Out-Null }

Write-Host "Monitoring: $SourceDir"
Write-Host "Target:     $DestDir"
Write-Host "Press Ctrl+C to stop."
Write-Host ""

while ($true) {
    $files = Get-ChildItem -LiteralPath $SourceDir -File | Where-Object { $_.Extension -ne ".jpg" }

    foreach ($file in $files) {
        $sourcePath = $file.FullName
        $destPath = Join-Path -Path $DestDir -ChildPath $file.Name

        try {
            # Try to open the file with exclusive access to check if it's locked
            $stream = [System.IO.File]::Open($sourcePath, 'Open', 'ReadWrite', 'None')
            $stream.Close()
            $stream.Dispose()
            
            # The file was unlocked at the check; producers must finish before
            # releasing their handle (an unlocked pause cannot be detected).
            Write-Host "[MOVE] Moving $($file.Name)..." -ForegroundColor Green
            # File.Move treats names literally and refuses an existing target,
            # including a target created after our exclusive-access check.
            [System.IO.File]::Move($sourcePath, $destPath)
        }
        catch {
            Write-Host "[SKIP] $($file.Name): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Start-Sleep -Seconds 5
}
