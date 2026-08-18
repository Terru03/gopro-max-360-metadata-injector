@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ============================================================================
:: GoPro Flat Video Metadata Injector
:: Re-injects GPS/telemetry/date metadata from an original .360 source into a
:: flat Premiere/Media Encoder MP4. GPMF is located dynamically and capped to
:: the rendered video's own duration so source telemetry can never extend it.
:: ============================================================================

call "%~dp0config.bat"

set "PREMIERE_DIR=%PREMIERE_EXPORT_DIR%"
set "SRC360_DIR=%SOURCE_360_DIR%"
set "OUTPUT_DIR=%OUTPUT_DIR%"
set "VERIFY_SCRIPT=%~dp0verify_video_integrity.ps1"

if not "%~1"=="" set "PREMIERE_DIR=%~1"
if not "%~2"=="" set "SRC360_DIR=%~2"
if not "%~3"=="" set "OUTPUT_DIR=%~3"

for /F %%a in ('echo prompt $E ^| cmd 2^>nul') do set "ESC=%%a"

set /a PROCESSED=0
set /a ERRORS=0
set /a MISSING=0
set /a SUCCESS=0
set /a NO_GPMF=0

where ffmpeg >nul 2>&1
if errorlevel 1 (
    echo ERROR: ffmpeg is not available in PATH.
    exit /b 1
)
where ffprobe >nul 2>&1
if errorlevel 1 (
    echo ERROR: ffprobe is not available in PATH.
    exit /b 1
)
where exiftool >nul 2>&1
if errorlevel 1 (
    echo ERROR: exiftool is not available in PATH.
    exit /b 1
)
if not exist "%VERIFY_SCRIPT%" (
    echo ERROR: verify_video_integrity.ps1 is missing.
    exit /b 1
)

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

if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

if !TOTAL! EQU 0 (
    echo   No MP4 files found in Premiere exports folder.
    echo.
    goto :summary
)

for /f "delims=" %%F in ('dir /b /s "%PREMIERE_DIR%\*.mp4" 2^>nul') do (
    set /a PROCESSED+=1
    set "MP4_PATH=%%F"
    set "MP4_NAME=%%~nF"
    set "MP4_FILE=%%~nxF"
    set "SRC360_PATH=!SRC360_DIR!\!MP4_NAME!.360"

    set "LAT="
    set "LON="
    set "ALT="
    set "GPMF_STREAM="
    set "RENDER_DURATION="
    set "PIPELINE_OK=1"
    set "USED_GPMF=0"

    <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] Processing: !MP4_FILE!"

    if not exist "!SRC360_PATH!" (
        set /a MISSING+=1
        <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - SKIP: No matching .360"
        echo.
    ) else (
        set "TEMP_FILE=!TEMP!\!MP4_NAME!_flat_working.mp4"
        set "TEMP_GPMF=!TEMP!\!MP4_NAME!_flat_gpmf.mp4"

        if exist "!TEMP_FILE!" del /f /q "!TEMP_FILE!" >nul 2>&1
        if exist "!TEMP_GPMF!" del /f /q "!TEMP_GPMF!" >nul 2>&1

        copy /y "!MP4_PATH!" "!TEMP_FILE!" >nul 2>&1
        if not exist "!TEMP_FILE!" (
            set "PIPELINE_OK=0"
            set /a ERRORS+=1
            echo.
            echo   ERROR: Could not copy !MP4_FILE! to the temporary folder.
        )

        if "!PIPELINE_OK!"=="1" (
            :: Extract the first GPS sample with a valid 3D lock.
            set "GPS_DATA="
            set "GPS_ISO6709="
            set "GPS_LINE=0"
            for /f "tokens=*" %%G in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0extract_first_locked_gps.ps1" "!SRC360_PATH!" 2^>nul') do (
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
            )

            for /f "delims=" %%D in ('ffprobe -v error -select_streams v:0 -show_entries stream^=duration -of default^=nw^=1:nk^=1 "!MP4_PATH!" 2^>nul') do if not defined RENDER_DURATION set "RENDER_DURATION=%%D"

            :: Locate gpmd dynamically. Different GoPro modes can place it at
            :: different global stream indexes.
            for /f "tokens=1,2 delims=," %%A in ('ffprobe -v error -select_streams d -show_entries stream^=index^,codec_tag_string -of csv^=p^=0 "!SRC360_PATH!" 2^>nul') do (
                if /I "%%B"=="gpmd" if not defined GPMF_STREAM set "GPMF_STREAM=%%A"
            )

            if defined GPMF_STREAM (
                set "USED_GPMF=1"
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Injecting GPMF stream !GPMF_STREAM!..."

                if defined RENDER_DURATION (
                    ffmpeg -y -v error -i "!TEMP_FILE!" -i "!SRC360_PATH!" -map 0 -map 1:!GPMF_STREAM! -map_metadata 0 -c copy -t !RENDER_DURATION! "!TEMP_GPMF!" >nul 2>&1
                ) else (
                    ffmpeg -y -v error -i "!TEMP_FILE!" -i "!SRC360_PATH!" -map 0 -map 1:!GPMF_STREAM! -map_metadata 0 -c copy -shortest "!TEMP_GPMF!" >nul 2>&1
                )

                if exist "!TEMP_GPMF!" (
                    move /y "!TEMP_GPMF!" "!TEMP_FILE!" >nul 2>&1
                ) else (
                    set "PIPELINE_OK=0"
                    set /a ERRORS+=1
                    echo.
                    echo   ERROR: GPMF injection failed.
                )
            ) else (
                set /a NO_GPMF+=1
                echo.
                echo   WARNING: No gpmd telemetry stream found in !SRC360_PATH!
            )
        )

        if "!PIPELINE_OK!"=="1" (
            exiftool -overwrite_original -TagsFromFile "!SRC360_PATH!" "-CreateDate" "-ModifyDate" "-TrackCreateDate" "-TrackModifyDate" "-MediaCreateDate" "-MediaModifyDate" "!TEMP_FILE!" >nul 2>&1

            if defined GPS_DATA (
                exiftool -overwrite_original -n "-Keys:GPSCoordinates=!GPS_ISO6709!" "-UserData:GPSCoordinates=!GPS_ISO6709!" -XMP-exif:GPSLatitude="!LAT!" -XMP-exif:GPSLongitude="!LON!" -XMP-exif:GPSAltitude="!ALT!" -XMP-exif:GPSAltitudeRef=0 "!TEMP_FILE!" >nul 2>&1
                exiftool -overwrite_original "-UserData:LocationInformation=" "!TEMP_FILE!" >nul 2>&1
            )

            set "EXPOSURE_DATA="
            for /f "tokens=*" %%E in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0extract_exposure_range.ps1" "!SRC360_PATH!" 2^>nul') do set "EXPOSURE_DATA=%%E"

            set "ISO_RANGE="
            set "SHUTTER_RANGE="
            for /f "tokens=1,2 delims=|" %%A in ("!EXPOSURE_DATA!") do (
                set "ISO_RANGE=%%A"
                set "SHUTTER_RANGE=%%B"
            )

            if defined ISO_RANGE (
                set "EXPOSURE_INFO=ISO !ISO_RANGE!, Shutter !SHUTTER_RANGE!"
                exiftool -overwrite_original -Make="GoPro" -Model="GoPro MAX2" "-UserComment=!EXPOSURE_INFO!" "-Description=!EXPOSURE_INFO!" "!TEMP_FILE!" >nul 2>&1
            ) else (
                exiftool -overwrite_original -Make="GoPro" -Model="GoPro MAX2" "!TEMP_FILE!" >nul 2>&1
            )

            :: Verify that metadata rewriting did not alter the actual video.
            set "VERIFY_RESULT="
            for /f "tokens=*" %%V in ('powershell -NoProfile -ExecutionPolicy Bypass -File "!VERIFY_SCRIPT!" -Reference "!MP4_PATH!" -Candidate "!TEMP_FILE!" 2^>^&1') do set "VERIFY_RESULT=%%V"
            echo(!VERIFY_RESULT! | findstr /B /C:"OK:" >nul
            if errorlevel 1 (
                set "PIPELINE_OK=0"
                set /a ERRORS+=1
                echo.
                echo   !VERIFY_RESULT!
                echo   Original export preserved: !MP4_PATH!
            )

            if "!PIPELINE_OK!"=="1" if "!USED_GPMF!"=="1" (
                set "FINAL_GPMF="
                for /f "tokens=*" %%G in ('ffprobe -v error -select_streams d -show_entries stream^=codec_tag_string -of csv^=p^=0 "!TEMP_FILE!" 2^>nul ^| findstr /I "gpmd"') do set "FINAL_GPMF=1"
                if not defined FINAL_GPMF (
                    set "PIPELINE_OK=0"
                    set /a ERRORS+=1
                    echo.
                    echo   ERROR: final file lost the gpmd telemetry stream.
                    echo   Original export preserved: !MP4_PATH!
                )
            )
        )

        if "!PIPELINE_OK!"=="1" (
            move /y "!TEMP_FILE!" "!OUTPUT_DIR!\!MP4_FILE!" >nul 2>&1
            if errorlevel 1 (
                set /a ERRORS+=1
                echo.
                echo   ERROR: Could not move !MP4_FILE! to output folder.
            ) else (
                set /a SUCCESS+=1
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - OK"
                echo.
                del /f /q "!MP4_PATH!" >nul 2>&1
            )
        ) else (
            if exist "!TEMP_FILE!" del /f /q "!TEMP_FILE!" >nul 2>&1
        )

        if exist "!TEMP_GPMF!" del /f /q "!TEMP_GPMF!" >nul 2>&1
    )
)

:summary
echo.
echo ============================================================================
echo   SUMMARY
echo ============================================================================
echo.
echo   Total MP4s:          !TOTAL!
echo   Successfully tagged: !SUCCESS!
echo   Errors:              !ERRORS!
echo   Missing .360:        !MISSING!
echo   No GPMF stream:      !NO_GPMF!
echo.
echo   Output folder: %OUTPUT_DIR%
echo.
echo ============================================================================
echo.

pause
endlocal
