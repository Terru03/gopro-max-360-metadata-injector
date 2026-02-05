# GoPro MAX 360 Metadata Injector

Windows batch scripts that inject 360° metadata into GoPro MAX photos and videos, making them viewable as immersive 360° content in Google Photos, Facebook, and other platforms.

## The Problem

GoPro MAX exports (from GoPro Player or Adobe Premiere) lose their 360° metadata. When you upload these files to Google Photos, they appear as flat, distorted equirectangular images instead of interactive 360° content.

## The Solution

These scripts:
1. Match rendered files with their original `.360` / `.36P` source files
2. Copy GPS coordinates and timestamps from the originals
3. Inject the required XMP-GPano (photos) or XMP-GSpherical (videos) metadata
4. Verify the injection was successful
5. Move processed files to an output folder

## Prerequisites

- **[ExifTool](https://exiftool.org/)** - Must be installed and available in your PATH
- **Windows 10/11** - Scripts use Windows batch/PowerShell

## Folder Structure

```
📁 Your Project Folder/
├── 📁 1 - .360 files/          # Original GoPro MAX files (.360, .36P)
├── 📁 2 - Render/              # Rendered MP4 videos awaiting processing
├── 📁 3 - Output/              # Processed files ready for upload
├── 📁 4 - GoPro Player Exports/# Exported JPG photos awaiting processing
├── 📁 5 - Premiere Watch Folder/# Adobe Media Encoder watch folder
├── config.bat                  # Path configuration
├── inject_360_photos.bat       # Photo metadata injector
├── inject_360_videos.bat       # Video metadata injector
├── run_watch_folder.bat        # Watch folder automation
└── safe_move.ps1               # Safe file mover utility
```

## Setup

1. Clone this repository
2. Edit `config.bat` to set your folder paths
3. Ensure ExifTool is installed and in your PATH

## Usage

### Inject 360 Metadata into Photos
```batch
inject_360_photos.bat
```
Processes JPG files in `4 - GoPro Player Exports/`, matching them with `.36P` files in `1 - .360 files/`.

### Inject 360 Metadata into Videos
```batch
inject_360_videos.bat
```
Processes MP4 files in `2 - Render/`, matching them with `.360` files in `1 - .360 files/`.

### Watch Folder Automation
```batch
run_watch_folder.bat
```
Launches Adobe Media Encoder and monitors the staging folder, safely moving completed files to the watch folder.

## How It Works

### Photo Injection (`inject_360_photos.bat`)
- Strips existing XMP metadata (removes conflicting GoPro tags)
- Copies GPS, timestamps, camera settings from `.36P` source
- Injects XMP-GPano tags: `UsePanoramaViewer=True`, `ProjectionType=equirectangular`
- Sets full panorama dimensions and pose angles

### Video Injection (`inject_360_videos.bat`)
- Copies GPS, timestamps, camera settings from `.360` source
- Injects XMP-GSpherical tags: `Spherical=true`, `Stitched=true`, `ProjectionType=equirectangular`

## Verification

After processing, the scripts verify that the 360° tags were successfully written before moving files to the output folder. Files that fail verification are flagged with a warning.

## License

MIT License - See [LICENSE](LICENSE) for details.
