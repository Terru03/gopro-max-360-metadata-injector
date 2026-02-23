@echo off
:: ============================================================================
:: GoPro MAX 360 Metadata Injector - Configuration
:: ============================================================================
:: Edit these paths to match your folder structure.
:: All paths should be absolute paths without trailing backslashes.
:: ============================================================================

:: Base directory (parent of "6 - GitHub" folder where these scripts live)
set "BASE_DIR=%~dp0.."

:: Source folder for original .360 and .36P files
set "SOURCE_360_DIR=%BASE_DIR%\1 - .360 files"

:: Folder for rendered MP4 videos awaiting metadata injection
set "RENDER_DIR=%BASE_DIR%\2 - Render"

:: Output folder for processed files ready for upload
set "OUTPUT_DIR=%BASE_DIR%\3 - Output"

:: Folder for GoPro Player photo exports awaiting metadata injection
set "PHOTO_EXPORT_DIR=%BASE_DIR%\4 - GoPro Player Exports"

:: Premiere Pro exports folder (flat video edits awaiting metadata re-injection)
set "PREMIERE_EXPORT_DIR=%BASE_DIR%\6 - Premiere Exports"

:: Adobe Media Encoder watch folder
set "WATCH_FOLDER_DIR=%BASE_DIR%\5 - Premiere Watch Folder"

:: Path to Adobe Media Encoder (for watch folder automation)
set "AME_PATH=C:\Program Files\Adobe\Adobe Media Encoder 2026\Adobe Media Encoder.exe"
