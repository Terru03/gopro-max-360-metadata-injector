@echo off
:: ============================================================================
:: GoPro Safe Watch Folder Mover
:: Launches Adobe Media Encoder and monitors staging folder
:: ============================================================================

:: Load configuration
call "%~dp0config.bat"

title GoPro Safe Watch Folder Mover
start "" "%AME_PATH%"
timeout /t 5 >nul
powershell -ExecutionPolicy Bypass -File "%~dp0safe_move.ps1" -SourceDir "%PHOTO_EXPORT_DIR%" -DestDir "%WATCH_FOLDER_DIR%"
pause
