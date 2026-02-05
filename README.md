# GoPro MAX 360 Metadata Injector

Windows batch scripts that inject 360° metadata into GoPro MAX photos and videos, making them viewable as immersive 360° content in Google Photos, Facebook, and other platforms.

## The Problem

GoPro MAX exports (from GoPro Player or Adobe Premiere) lose their 360° metadata. When you upload these files to Google Photos, they appear as flat, distorted equirectangular images instead of interactive 360° content.

## The Solution

These scripts restore the missing metadata by:
1. Matching rendered files with their original `.360` / `.36P` source files
2. Copying GPS coordinates and timestamps from the originals
3. Injecting the required XMP-GPano (photos) or XMP-GSpherical (videos) metadata
4. Verifying the injection was successful
5. Moving processed files to an output folder ready for upload

---

## Prerequisites

- **[ExifTool](https://exiftool.org/)** - Must be installed and available in your PATH
- **[Python 3.x](https://www.python.org/)** - Required for Google's spatial-media tool (video metadata)
- **Windows 10/11** - Scripts use Windows batch/PowerShell
- **GoPro Player** - For exporting 360° photos and videos
- **Adobe Premiere Pro + Media Encoder** *(optional)* - For advanced video editing workflow

---

## Folder Structure

```
📁 Your Project Folder/
├── 📁 1 - .360 files/            # Original GoPro MAX files (.360, .36P)
├── 📁 2 - Render/                # Rendered MP4 videos awaiting metadata injection
├── 📁 3 - Output/                # ✅ Processed files ready for upload
├── 📁 4 - GoPro Player Exports/  # Exported JPG photos awaiting metadata injection
├── 📁 5 - Premiere Watch Folder/ # Adobe Media Encoder watch folder
├── config.bat                    # Path configuration
├── inject_360_photos.bat         # Photo metadata injector
├── inject_360_videos.bat         # Video metadata injector
├── run_watch_folder.bat          # Watch folder automation
└── safe_move.ps1                 # Safe file mover utility
```

---

## Setup

1. **Clone this repository** to your desired location
2. **Edit `config.bat`** to set your folder paths (if different from defaults)
3. **Install ExifTool**:
   - Download from [exiftool.org](https://exiftool.org/)
   - Rename `exiftool(-k).exe` to `exiftool.exe`
   - Add to your system PATH or place in the script folder

---

## Complete Workflow

### 📷 For 360° Photos

| Step | Action | Details |
|------|--------|---------|
| 1 | **Import** | Copy your `.360` files from GoPro MAX to `1 - .360 files/` |
| 2 | **Export in GoPro Player** | Open each `.360` file in GoPro Player → File → Export → Save as JPG to `4 - GoPro Player Exports/` |
| 3 | **Run the script** | Double-click `inject_360_photos.bat` |
| 4 | **Upload** | Find your processed photos in `3 - Output/` → Upload to Google Photos |

**What the script does automatically:**
- Matches each JPG with its original `.36P` source file (by filename)
- Strips conflicting XMP metadata from GoPro Player export
- Copies GPS coordinates, timestamps, camera make/model from original
- Injects XMP-GPano tags for 360° viewer recognition
- Verifies injection succeeded before moving to output

---

### 🎬 For 360° Videos (Simple Workflow)

| Step | Action | Details |
|------|--------|---------|
| 1 | **Import** | Copy your `.360` files from GoPro MAX to `1 - .360 files/` |
| 2 | **Export in GoPro Player** | Open each `.360` → File → Export → Choose quality → Save as MP4 to `2 - Render/` |
| 3 | **Run the script** | Double-click `inject_360_videos.bat` |
| 4 | **Upload** | Find your processed videos in `3 - Output/` → Upload to Google Photos |

---

### 🎬 For 360° Videos (Adobe Premiere Workflow)

For more control over editing, you can use Adobe Premiere Pro with the watch folder automation:

| Step | Action | Details |
|------|--------|---------|
| 1 | **Import** | Copy your `.360` files to `1 - .360 files/` |
| 2 | **Export from GoPro Player** | Export as `.mov` (for editing) to `4 - GoPro Player Exports/` |
| 3 | **Start watch folder** | Run `run_watch_folder.bat` — this launches Adobe Media Encoder and monitors for new files |
| 4 | **Edit in Premiere** | Import the `.mov` files into Premiere Pro, edit as needed |
| 5 | **Queue in Media Encoder** | Send your sequence to Adobe Media Encoder → Output to `2 - Render/` as H.264 MP4 |
| 6 | **Inject metadata** | Run `inject_360_videos.bat` |
| 7 | **Upload** | Find your processed videos in `3 - Output/` |

**What `run_watch_folder.bat` does:**
- Launches Adobe Media Encoder
- Monitors `4 - GoPro Player Exports/` for new files
- Safely moves files to the watch folder only when fully written (prevents encoding corruption)

---

## Script Details

### `inject_360_photos.bat`
- **Input:** JPG files in `4 - GoPro Player Exports/`
- **Matches with:** `.36P` files in `1 - .360 files/`
- **Output:** `3 - Output/`
- **Injects:** XMP-GPano tags (`UsePanoramaViewer=True`, `ProjectionType=equirectangular`, panorama dimensions, pose angles)

### `inject_360_videos.bat`
- **Input:** MP4 files in `2 - Render/`
- **Matches with:** `.360` files in `1 - .360 files/`
- **Output:** `3 - Output/`
- **Injects:** XMP-GSpherical tags (`Spherical=true`, `Stitched=true`, `ProjectionType=equirectangular`)

### `config.bat`
Central configuration file for all folder paths. Edit this to customize for your setup.

---

## Verification

After processing, the scripts automatically:
1. ✅ Verify that 360° tags were successfully written
2. ✅ Move verified files to the output folder
3. ⚠️ Flag files that fail verification with a warning
4. 📊 Display a summary with success/error counts

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "exiftool is not recognized" | Add ExifTool to your system PATH |
| "No matching .360 file" | Ensure filenames match between export and original |
| Photo not showing as 360° | Check that the source was a 360° photo (not a reframed export) |
| Video not showing as 360° | Try re-uploading; some platforms take time to process 360° |

---

## License

MIT License - See [LICENSE](LICENSE) for details.
