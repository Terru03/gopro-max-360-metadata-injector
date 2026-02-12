# ==============================================================================
# Safe Watch Folder Mover
# Moves files from Staging to Watch Folder only when they are fully written.
# ==============================================================================
param(
    [string]$SourceDir = "P:\GoPro MAX 2\4 - GoPro Player Exports",
    [string]$DestDir = "P:\GoPro MAX 2\5 - Premiere Watch Folder"
)

# Create directories if they don't exist
if (!(Test-Path -Path $SourceDir)) { New-Item -ItemType Directory -Force -Path $SourceDir | Out-Null }
if (!(Test-Path -Path $DestDir)) { New-Item -ItemType Directory -Force -Path $DestDir | Out-Null }

Write-Host "Monitoring: $SourceDir"
Write-Host "Target:     $DestDir"
Write-Host "Press Ctrl+C to stop."
Write-Host ""

while ($true) {
    $files = Get-ChildItem -Path $SourceDir -File | Where-Object { $_.Extension -ne ".jpg" }

    foreach ($file in $files) {
        $sourcePath = $file.FullName
        $destPath = Join-Path -Path $DestDir -ChildPath $file.Name

        try {
            # Try to open the file with exclusive access to check if it's locked
            $stream = [System.IO.File]::Open($sourcePath, 'Open', 'ReadWrite', 'None')
            $stream.Close()
            $stream.Dispose()
            
            # If we get here, the file is NOT locked (writing is done)
            Write-Host "[MOVE] Moving $($file.Name)..." -ForegroundColor Green
            Move-Item -Path $sourcePath -Destination $destPath -Force
        }
        catch {
            # File is locked, skip it
            Write-Host "[BUSY] $($file.Name) is still being written..." -ForegroundColor Yellow
        }
    }

    Start-Sleep -Seconds 5
}
