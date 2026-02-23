
# Process "12 - Trips" safely by moving files to a temp folder and processing them back.

$tripsDir = "P:\GoPro MAX 2\12 - Trips"
$source360Dir = "P:\GoPro MAX 2\1 - .360 files"
$batScript = "P:\GoPro MAX 2\6 - GitHub\inject_360_videos.bat"
$ffmpegPath = "C:\Program Files\Studio 2.0\PhotoRealisticRenderer\win\64"

# Add FFmpeg to PATH for the session
$env:Path = "$ffmpegPath;$env:Path"

# Verify FFmpeg
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Error "FFmpeg not found in path even after adding it."
    exit 1
}

# Get all subfolders with MP4 files
$folders = Get-ChildItem -Path $tripsDir -Directory -Recurse | Where-Object { 
    (Get-ChildItem -Path $_.FullName -Filter "*.mp4").Count -gt 0 
}

foreach ($folder in $folders) {
    Write-Host "Processing folder: $($folder.FullName)" -ForegroundColor Cyan
    
    $tempDir = Join-Path $folder.FullName "_TempProcess"
    
    # Recovery: If temp dir exists and has files, move them back first
    if (Test-Path $tempDir) {
        $stuckFiles = Get-ChildItem -Path $tempDir -Filter "*.mp4"
        if ($stuckFiles.Count -gt 0) {
            Write-Warning "Found stuck files in temp dir. Restoring..."
            Move-Item -Path "$tempDir\*.mp4" -Destination $folder.FullName -Force
        }
        # Remove empty temp dir
        if ((Get-ChildItem $tempDir).Count -eq 0) {
            Remove-Item $tempDir -Force
        }
    }
    
    if (-not (Test-Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir | Out-Null
    }
    
    # Move MP4 files to temp dir
    $mp4Files = Get-ChildItem -Path $folder.FullName -Filter "*.mp4" 
    foreach ($file in $mp4Files) {
        Move-Item -Path $file.FullName -Destination $tempDir -Force
    }
    
    # Call the injection script
    # Usage: inject_360_videos.bat [RENDER_DIR] [SRC360_DIR] [OUTPUT_DIR]
    $cmd = "& '$batScript' '$tempDir' '$source360Dir' '$($folder.FullName)'"
    Invoke-Expression $cmd
    
    # Cleanup temp dir if empty
    if ((Get-ChildItem $tempDir).Count -eq 0) {
        Remove-Item $tempDir -Force
    }
    else {
        Write-Warning "Temp folder not empty: $tempDir"
    }
}

Write-Host "Done!" -ForegroundColor Green
