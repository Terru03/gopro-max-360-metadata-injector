@echo off
setlocal EnableDelayedExpansion

:: ============================================================================
:: GoPro MAX 360 Metadata Injector
:: Copies GPS/time metadata from .360 files and injects proper spherical video
:: metadata using Google's spatial-media tool for Google Photos recognition.
:: ============================================================================

:: Load configuration
call "%~dp0config.bat"

:: Set directories from config (can be overridden with arguments)
set "RENDER_DIR=%RENDER_DIR%"
set "SRC360_DIR=%SOURCE_360_DIR%"
set "OUTPUT_DIR=%OUTPUT_DIR%"
set "PLAYER_DIR=%WATCH_FOLDER_DIR%\Source"
set "SPATIALMEDIA=%~dp0spatialmedia"

:: Override with arguments if provided
if not "%~1"=="" set "RENDER_DIR=%~1"
if not "%~2"=="" set "SRC360_DIR=%~2"
if not "%~3"=="" set "OUTPUT_DIR=%~3"

:: Get ANSI escape character
for /F %%a in ('echo prompt $E ^| cmd 2^>nul') do set "ESC=%%a"

:: Counters
set /a PROCESSED=0
set /a ERRORS=0
set /a MISSING=0
set /a NOT360=0
set /a SUCCESS=0

:: Count total MP4 files
set /a TOTAL=0
for /f "delims=" %%F in ('dir /b /s "%RENDER_DIR%\*.mp4" 2^>nul') do set /a TOTAL+=1

echo.
echo ============================================================================
echo   GoPro MAX 360 Metadata Injector
echo ============================================================================
echo.
echo   Render folder: %RENDER_DIR%
echo   Source .360:   %SRC360_DIR%
echo   Output folder: %OUTPUT_DIR%
echo   Total MP4s:    !TOTAL!
echo.
echo ============================================================================
echo.

:: Create output directory if it doesn't exist
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

:: Exit early if no files found
if !TOTAL! EQU 0 (
    echo   No MP4 files found in render folder.
    echo.
    goto :summary
)

:: Process each MP4 in Render folder
for /f "delims=" %%F in ('dir /b /s "%RENDER_DIR%\*.mp4" 2^>nul') do (
    set /a PROCESSED+=1
    set "MP4_PATH=%%F"
    set "MP4_NAME=%%~nF"
    set "MP4_FILE=%%~nxF"
    set "SRC360_PATH=!SRC360_DIR!\!MP4_NAME!.360"
    
    :: Logic Fix: Reset GPS variables to prevent leakage from previous files
    set "LAT="
    set "LON="
    set "ALT="
    
    :: Progress line (updateable)
    <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] Processing: !MP4_FILE!"
    
    if not exist "!SRC360_PATH!" (
        set /a MISSING+=1
        <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - SKIP: No matching .360"
        echo.
    ) else (
        set "TEMP_FILE=!TEMP!\!MP4_FILE!"
        set "TEMP_OUT=!TEMP!\!MP4_NAME!_360.mp4"
        
        :: Clean up any existing temp files
        if exist "!TEMP_FILE!" del /f "!TEMP_FILE!" >nul 2>&1
        if exist "!TEMP_OUT!" del /f "!TEMP_OUT!" >nul 2>&1
        
        :: Copy to temp
        <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Copying..."
        copy /y "!MP4_PATH!" "!TEMP_FILE!" >nul 2>&1
        
        if not exist "!TEMP_FILE!" (
            set /a ERRORS+=1
            <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - ERROR: Copy failed"
            echo.
        ) else (
            :: Step 1: Inject GPMF Telemetry if ffmpeg is available (BEFORE spatial-media to avoid stripping metadata)
            where ffmpeg >nul 2>&1
            if !errorlevel! EQU 0 (
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Injecting GPMF telemetry..."
                set "TEMP_GPMF=!TEMP!\!MP4_NAME!_gpmf.mp4"
                if exist "!TEMP_GPMF!" del /f "!TEMP_GPMF!" >nul 2>&1
                
                :: Map video/audio from input (0) and GPMF (stream 3) from source (1)
                :: -map 0: copy all streams from TEMP_FILE (video/audio)
                :: -map 1:3 copy stream 3 from SRC360_PATH (GPMF)
                :: Use TEMP_FILE as input, map to TEMP_GPMF
                ffmpeg -y -v error -i "!TEMP_FILE!" -i "!SRC360_PATH!" -map 0 -map 1:3 -c copy -tag:d:1 gpmd "!TEMP_GPMF!" >nul 2>&1
                
                if exist "!TEMP_GPMF!" (
                    move /y "!TEMP_GPMF!" "!TEMP_FILE!" >nul 2>&1
                ) else (
                    <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - WARNING: GPMF injection failed"
                    echo.
                )
            )

            :: Step 2: Inject spherical metadata using Google's spatial-media tool
            :: (This creates a new file, so we do this before adding other metadata)
            <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Injecting 360 metadata..."
            python "!SPATIALMEDIA!" -i "!TEMP_FILE!" "!TEMP_OUT!" >nul 2>&1
            
            if not exist "!TEMP_OUT!" (
                set /a ERRORS+=1
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - ERROR: spatial-media failed"
                echo.
                del /f "!TEMP_FILE!" >nul 2>&1
            ) else (

                

                
                :: Step 2: Inject Metadata (Dates, GPS) - Run AFTER ffmpeg to ensure metadata persistence
                exiftool -overwrite_original -TagsFromFile "!SRC360_PATH!" "-GPS*" "-CreateDate" "-ModifyDate" "-TrackCreateDate" "-TrackModifyDate" "-MediaCreateDate" "-MediaModifyDate" "!TEMP_OUT!" >nul 2>&1
                
                :: Step 2.5: Recover GPS if not found in static tags (common with Quick Capture)
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Checking for delayed GPS lock..."
                set "HAS_GPS="
                for /f "tokens=*" %%G in ('exiftool -GPSLatitude -n "!TEMP_OUT!" 2^>nul') do set "HAS_GPS=%%G"
                
                :: If GPS is missing or 0, try to extract from telemetry
                set "TRY_TELEMETRY=0"
                if not defined HAS_GPS set "TRY_TELEMETRY=1"
                echo !HAS_GPS! | findstr /C:": 0" >nul && set "TRY_TELEMETRY=1"
                


                :: If we ALREADY have GPS (from standard tags), copy it to Keys/UserData ensuring Google Photos sees it.
                if "!TRY_TELEMETRY!"=="0" (
                    <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Syncing standard GPS to Keys..."
                    :: Use numerical values (#) to ensure compatibility with Keys:GPSCoordinates
                    exiftool -overwrite_original "-Keys:GPSCoordinates<$XMP:GPSLatitude# $XMP:GPSLongitude# $XMP:GPSAltitude#" "-UserData:GPSCoordinates<$XMP:GPSLatitude# $XMP:GPSLongitude# $XMP:GPSAltitude#" "!TEMP_OUT!" >nul 2>&1
                    
                    :: Fallback if Altitude is missing
                    if errorlevel 1 (
                         exiftool -overwrite_original "-Keys:GPSCoordinates<$XMP:GPSLatitude# $XMP:GPSLongitude#" "-UserData:GPSCoordinates<$XMP:GPSLatitude# $XMP:GPSLongitude#" "!TEMP_OUT!" >nul 2>&1
                    )
                )

                if "!TRY_TELEMETRY!"=="1" (
                    <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Recovering GPS from telemetry..."
                    set "RECOVERED_GPS="
                    :: Extract Lat, Lon, Alt (default 0)
                    for /f "tokens=1,2,3 delims=," %%A in ('powershell -ExecutionPolicy Bypass -Command "$gps = exiftool -ee3 -n -p '$GPSLatitude,$GPSLongitude,$GPSAltitude' '!SRC360_PATH!' 2>$null | ForEach-Object { $p = $_.Split(','); if ($p[0] -ne '0' -and $p[1] -ne '0') { $_; break } } | Select-Object -First 1; if ($gps) { $gps } else { '' }"') do (
                        set "LAT=%%A"
                        set "LON=%%B"
                        set "ALT=%%C"
                        if "!ALT!"=="" set "ALT=0"
                        if not "!LAT!"=="" (
                            :: Construct ISO6709 string for QuickTime/Keys (e.g., "+27.5916+086.5640+0000/") - actually Exiftool handles decimal input for these tags too usually, but Keys:GPSCoordinates prefers "lat lon alt" or generic.
                            :: Exiftool's -Keys:GPSCoordinates accepts "Lat Lon Alt" directly.
                            
                            :: Inject into multiple standard tags for maximum compatibility (Keys for Android/Google, UserData for Apple)
                            exiftool -overwrite_original -Keys:GPSCoordinates="!LAT! !LON! !ALT!" -UserData:GPSCoordinates="!LAT! !LON! !ALT!" -GPSLatitude="!LAT!" -GPSLongitude="!LON!" -GPSLatitudeRef="!LAT!" -GPSLongitudeRef="!LON!" -GPSAltitude="!ALT!" -GPSAltitudeRef="!ALT!" "!TEMP_OUT!" >nul 2>&1
                        )
                    )
                )
                
                :: Step 3: Extract ISO and shutter speed range from GoPro telemetry
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Extracting exposure data..."
                set "EXPOSURE_DATA="
                for /f "tokens=*" %%E in ('powershell -ExecutionPolicy Bypass -File "%~dp0extract_exposure_range.ps1" "!SRC360_PATH!" 2^>nul') do set "EXPOSURE_DATA=%%E"
                
                :: Parse ISO and Shutter from pipe-separated output (format: "ISO_RANGE|SHUTTER_RANGE")
                set "ISO_RANGE="
                set "SHUTTER_RANGE="
                for /f "tokens=1,2 delims=|" %%A in ("!EXPOSURE_DATA!") do (
                    set "ISO_RANGE=%%A"
                    set "SHUTTER_RANGE=%%B"
                )
                
                :: Step 4: Set Make, Model, and exposure info
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Setting camera info..."
                if defined ISO_RANGE (
                    set "EXPOSURE_INFO=ISO !ISO_RANGE!, Shutter !SHUTTER_RANGE!"
                    exiftool -overwrite_original -Make="GoPro" -Model="GoPro MAX2" "-UserComment=!EXPOSURE_INFO!" "-Description=!EXPOSURE_INFO!" "!TEMP_OUT!" >nul 2>&1
                ) else (
                    exiftool -overwrite_original -Make="GoPro" -Model="GoPro MAX2" "!TEMP_OUT!" >nul 2>&1
                )
                
                :: Verify spherical metadata was injected
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Verifying..."
                set "SPHERICAL_CHECK="
                for /f "tokens=*" %%V in ('python "!SPATIALMEDIA!" "!TEMP_OUT!" 2^>nul ^| findstr /i "Spherical"') do set "SPHERICAL_CHECK=%%V"
                
                if defined SPHERICAL_CHECK (
                    :: Move to output folder
                    move /y "!TEMP_OUT!" "!OUTPUT_DIR!\!MP4_FILE!" >nul 2>&1
                    if errorlevel 1 (
                        set /a ERRORS+=1
                        <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - ERROR: Move failed"
                        echo.
                    ) else (
                        set /a SUCCESS+=1
                        <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - OK"
                        echo.
                        
                        REM Delete original from Render folder
                        del "!MP4_PATH!" >nul 2>&1
                        
                        REM Delete processed files from Watch Folder Source (any extension)
                        for %%D in ("!PLAYER_DIR!\!MP4_NAME!.*") do (
                            del "%%D" >nul 2>&1
                        )
                    )
                ) else (
                    set /a NOT360+=1
                    <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - WARNING: 360 metadata not verified"
                    echo.
                    :: Still move to output, may work
                    move /y "!TEMP_OUT!" "!OUTPUT_DIR!\!MP4_FILE!" >nul 2>&1
                )
                
                :: Clean up temp file
                del /f "!TEMP_FILE!" >nul 2>&1
            )
        )
    )
)

:summary
echo.
echo.
echo ============================================================================
echo   SUMMARY
echo ============================================================================
echo.
echo   Total MP4s:          !TOTAL!
echo   Successfully tagged: !SUCCESS!
echo   Errors:              !ERRORS!
echo   Missing .360:        !MISSING!
echo   Verification failed: !NOT360!
echo.
echo   Output folder: %OUTPUT_DIR%
echo.
echo ============================================================================

REM pause
