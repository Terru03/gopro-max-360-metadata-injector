@echo off
setlocal EnableDelayedExpansion

:: ============================================================================
:: GoPro Flat Video Metadata Injector
:: Re-injects GPS/telemetry/date metadata from original .360 source files
:: into flat (non-360) Premiere Pro exports. Does NOT inject spherical/360
:: metadata since the export is a standard flat video.
:: ============================================================================

:: Load configuration
call "%~dp0config.bat"

:: Set directories from config (can be overridden with arguments)
set "PREMIERE_DIR=%PREMIERE_EXPORT_DIR%"
set "SRC360_DIR=%SOURCE_360_DIR%"
set "OUTPUT_DIR=%OUTPUT_DIR%"

:: Override with arguments if provided
if not "%~1"=="" set "PREMIERE_DIR=%~1"
if not "%~2"=="" set "SRC360_DIR=%~2"
if not "%~3"=="" set "OUTPUT_DIR=%~3"

:: Get ANSI escape character
for /F %%a in ('echo prompt $E ^| cmd 2^>nul') do set "ESC=%%a"

:: Counters
set /a PROCESSED=0
set /a ERRORS=0
set /a MISSING=0
set /a SUCCESS=0

:: Count total MP4 files
set /a TOTAL=0
for /f "delims=" %%F in ('dir /b /s "%PREMIERE_DIR%\*.mp4" 2^>nul') do set /a TOTAL+=1

echo.
echo ============================================================================
echo   GoPro Flat Video Metadata Injector
echo ============================================================================
echo.
echo   Premiere exports: %PREMIERE_DIR%
echo   Source .360:      %SRC360_DIR%
echo   Output folder:    %OUTPUT_DIR%
echo   Total MP4s:       !TOTAL!
echo.
echo ============================================================================
echo.

:: Create output directory if it doesn't exist
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

:: Exit early if no files found
if !TOTAL! EQU 0 (
    echo   No MP4 files found in Premiere exports folder.
    echo.
    goto :summary
)

:: Process each MP4 in Premiere exports folder
for /f "delims=" %%F in ('dir /b /s "%PREMIERE_DIR%\*.mp4" 2^>nul') do (
    set /a PROCESSED+=1
    set "MP4_PATH=%%F"
    set "MP4_NAME=%%~nF"
    set "MP4_FILE=%%~nxF"
    set "SRC360_PATH=!SRC360_DIR!\!MP4_NAME!.360"

    REM Reset GPS variables to prevent leakage from previous files
    set "LAT="
    set "LON="
    set "ALT="

    REM Progress line
    <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] Processing: !MP4_FILE!"

    if not exist "!SRC360_PATH!" (
        set /a MISSING+=1
        <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - SKIP: No matching .360"
        echo.
    ) else (
        set "TEMP_FILE=!TEMP!\!MP4_FILE!"

        REM Clean up any existing temp files
        if exist "!TEMP_FILE!" del /f "!TEMP_FILE!" >nul 2>&1

        REM Copy to temp
        <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Copying..."
        copy /y "!MP4_PATH!" "!TEMP_FILE!" >nul 2>&1

        if not exist "!TEMP_FILE!" (
            set /a ERRORS+=1
            <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - ERROR: Copy failed"
            echo.
        ) else (
            REM Step 1: Extract first GPS-locked position from GPMF telemetry BEFORE ffmpeg
            <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Extracting first locked GPS from telemetry..."
            set "GPS_DATA="
            set "GPS_ISO6709="
            set "GPS_LINE=0"
            for /f "tokens=*" %%G in ('powershell -ExecutionPolicy Bypass -File "%~dp0extract_first_locked_gps.ps1" "!SRC360_PATH!" 2^>nul') do (
                set /a GPS_LINE+=1
                if !GPS_LINE! EQU 1 set "GPS_DATA=%%G"
                if !GPS_LINE! EQU 2 set "GPS_ISO6709=%%G"
            )

            if defined GPS_DATA (
                for /f "tokens=1,2,3 delims=," %%A in ("!GPS_DATA!") do (
                    set "LAT=%%A"
                    set "LON=%%B"
                    set "ALT=%%C"
                )
                if "!ALT!"=="" set "ALT=0"
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Locked GPS: !LAT!, !LON!, !ALT!m"
            ) else (
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - WARNING: No locked GPS found"
                echo.
            )

            REM Step 2: Inject GPMF Telemetry via ffmpeg, include location metadata if GPS was found
            where ffmpeg >nul 2>&1
            if !errorlevel! EQU 0 (
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Injecting GPMF telemetry..."
                set "TEMP_GPMF=!TEMP!\!MP4_NAME!_gpmf.mp4"
                if exist "!TEMP_GPMF!" del /f "!TEMP_GPMF!" >nul 2>&1

                REM Map video/audio from input, stream 3 GPMF from source
                REM Do NOT write location via ffmpeg to avoid conflicting loci atom
                ffmpeg -y -v error -i "!TEMP_FILE!" -i "!SRC360_PATH!" -map 0 -map 1:3 -c copy -tag:d:1 gpmd "!TEMP_GPMF!" >nul 2>&1

                if exist "!TEMP_GPMF!" (
                    move /y "!TEMP_GPMF!" "!TEMP_FILE!" >nul 2>&1
                ) else (
                    <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - WARNING: GPMF injection failed"
                    echo.
                )
            )

            REM Step 3: Inject Metadata - Dates only - via exiftool
            <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Injecting date metadata..."
            exiftool -overwrite_original -TagsFromFile "!SRC360_PATH!" "-CreateDate" "-ModifyDate" "-TrackCreateDate" "-TrackModifyDate" "-MediaCreateDate" "-MediaModifyDate" "!TEMP_FILE!" >nul 2>&1

            REM Step 4: Write GPS to metadata tags for all platforms
            if defined GPS_DATA (
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Writing GPS to metadata tags..."
                REM Keys:GPSCoordinates = Apple mdta com.apple.quicktime.location.ISO6709 - Google Photos, Apple
                REM UserData:GPSCoordinates = ©xyz atom in udta - phone galleries, Android MediaStore
                REM XMP-exif GPS tags = Windows, web, general metadata readers
                exiftool -overwrite_original -n "-Keys:GPSCoordinates=!GPS_ISO6709!" "-UserData:GPSCoordinates=!GPS_ISO6709!" -XMP-exif:GPSLatitude="!LAT!" -XMP-exif:GPSLongitude="!LON!" -XMP-exif:GPSAltitude="!ALT!" -XMP-exif:GPSAltitudeRef=0 "!TEMP_FILE!" >nul 2>&1
                REM Remove the loci atom that exiftool creates as a side-effect of UserData:GPSCoordinates
                REM loci has lower precision and conflicts with the accurate GPS in ©xyz and Keys
                exiftool -overwrite_original "-UserData:LocationInformation=" "!TEMP_FILE!" >nul 2>&1
            )

            REM Step 5: Extract ISO and shutter speed range from GoPro telemetry
            <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Extracting exposure data..."
            set "EXPOSURE_DATA="
            for /f "tokens=*" %%E in ('powershell -ExecutionPolicy Bypass -File "%~dp0extract_exposure_range.ps1" "!SRC360_PATH!" 2^>nul') do set "EXPOSURE_DATA=%%E"

            REM Parse ISO and Shutter from pipe-separated output
            set "ISO_RANGE="
            set "SHUTTER_RANGE="
            for /f "tokens=1,2 delims=|" %%A in ("!EXPOSURE_DATA!") do (
                set "ISO_RANGE=%%A"
                set "SHUTTER_RANGE=%%B"
            )

            REM Step 6: Set Make, Model, and exposure info
            <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Setting camera info..."
            if defined ISO_RANGE (
                set "EXPOSURE_INFO=ISO !ISO_RANGE!, Shutter !SHUTTER_RANGE!"
                exiftool -overwrite_original -Make="GoPro" -Model="GoPro MAX2" "-UserComment=!EXPOSURE_INFO!" "-Description=!EXPOSURE_INFO!" "!TEMP_FILE!" >nul 2>&1
            ) else (
                exiftool -overwrite_original -Make="GoPro" -Model="GoPro MAX2" "!TEMP_FILE!" >nul 2>&1
            )

            REM Move to output folder
            <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Moving to output..."
            move /y "!TEMP_FILE!" "!OUTPUT_DIR!\!MP4_FILE!" >nul 2>&1
            if errorlevel 1 (
                set /a ERRORS+=1
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - ERROR: Move failed"
                echo.
            ) else (
                set /a SUCCESS+=1
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - OK"
                echo.

                REM Delete original from Premiere exports folder
                del "!MP4_PATH!" >nul 2>&1
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
echo.
echo   Output folder: %OUTPUT_DIR%
echo.
echo ============================================================================

pause
