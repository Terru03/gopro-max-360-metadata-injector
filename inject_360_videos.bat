@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ============================================================================
:: GoPro MAX / MAX2 360 Metadata Injector
::
:: Preserves existing spherical metadata when present, dynamically finds the
:: GoPro GPMF telemetry stream, and verifies video integrity before deleting
:: the original render. Google's spatial-media tool is used only as a fallback
:: when the rendered MP4 does not already contain spherical metadata.
:: ============================================================================

call "%~dp0config.bat"

set "RENDER_DIR=%RENDER_DIR%"
set "SRC360_DIR=%SOURCE_360_DIR%"
set "OUTPUT_DIR=%OUTPUT_DIR%"
set "PLAYER_DIR=%WATCH_FOLDER_DIR%\Source"
set "SPATIALMEDIA=%~dp0spatialmedia"
set "VERIFY_SCRIPT=%~dp0verify_video_integrity.ps1"

if not "%~1"=="" set "RENDER_DIR=%~1"
if not "%~2"=="" set "SRC360_DIR=%~2"
if not "%~3"=="" set "OUTPUT_DIR=%~3"

for /F %%a in ('echo prompt $E ^| cmd 2^>nul') do set "ESC=%%a"

set /a PROCESSED=0
set /a ERRORS=0
set /a MISSING=0
set /a NOT360=0
set /a SUCCESS=0
set /a NO_GPMF=0
set /a SPATIAL_FALLBACKS=0

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
for /f "delims=" %%F in ('dir /b /s "%RENDER_DIR%\*.mp4" 2^>nul') do set /a TOTAL+=1

echo.
echo ============================================================================
echo   GoPro MAX / MAX2 360 Metadata Injector
echo ============================================================================
echo.
echo   Render folder: %RENDER_DIR%
echo   Source .360:   %SRC360_DIR%
echo   Output folder: %OUTPUT_DIR%
echo   Total MP4s:    !TOTAL!
echo.
echo ============================================================================
echo.

if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

if !TOTAL! EQU 0 (
    echo   No MP4 files found in render folder.
    echo.
    goto :summary
)

for /f "delims=" %%F in ('dir /b /s "%RENDER_DIR%\*.mp4" 2^>nul') do (
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
        set "TEMP_FILE=!TEMP!\!MP4_NAME!_working.mp4"
        set "TEMP_GPMF=!TEMP!\!MP4_NAME!_gpmf.mp4"
        set "TEMP_OUT=!TEMP!\!MP4_NAME!_360.mp4"

        if exist "!TEMP_FILE!" del /f /q "!TEMP_FILE!" >nul 2>&1
        if exist "!TEMP_GPMF!" del /f /q "!TEMP_GPMF!" >nul 2>&1
        if exist "!TEMP_OUT!" del /f /q "!TEMP_OUT!" >nul 2>&1

        <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Copying render..."
        copy /y "!MP4_PATH!" "!TEMP_FILE!" >nul 2>&1

        if not exist "!TEMP_FILE!" (
            set "PIPELINE_OK=0"
            set /a ERRORS+=1
            <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - ERROR: Copy failed"
            echo.
        )

        if "!PIPELINE_OK!"=="1" (
            for /f "delims=" %%D in ('ffprobe -v error -select_streams v:0 -show_entries stream^=duration -of default^=nw^=1:nk^=1 "!MP4_PATH!" 2^>nul') do if not defined RENDER_DURATION set "RENDER_DURATION=%%D"

            :: Locate the data stream tagged gpmd. Stream indexes differ between
            :: recording modes, so never assume a fixed index such as 1:3.
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
                    <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - ERROR: GPMF injection failed"
                    echo.
                )
            ) else (
                set /a NO_GPMF+=1
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - WARNING: No gpmd stream found"
                echo.
            )
        )

        if "!PIPELINE_OK!"=="1" (
            :: GoPro Player normally exports Spherical Video V2 metadata already.
            :: Preserve it rather than rewriting the entire MP4 unnecessarily.
            set "HAS_SPHERICAL="
            for /f "tokens=*" %%S in ('ffprobe -v error -select_streams v:0 -show_streams "!TEMP_FILE!" 2^>nul ^| findstr /I /C:"projection=equirectangular"') do set "HAS_SPHERICAL=1"

            if defined HAS_SPHERICAL (
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Preserving existing 360 metadata..."
                move /y "!TEMP_FILE!" "!TEMP_OUT!" >nul 2>&1
            ) else (
                set /a SPATIAL_FALLBACKS+=1
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - 360 metadata missing, using spatial-media fallback..."

                if not exist "!SPATIALMEDIA!" (
                    set "PIPELINE_OK=0"
                    set /a ERRORS+=1
                    <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - ERROR: spatialmedia fallback is missing"
                    echo.
                ) else (
                    python "!SPATIALMEDIA!" -i "!TEMP_FILE!" "!TEMP_OUT!" >nul 2>&1
                    if not exist "!TEMP_OUT!" (
                        set "PIPELINE_OK=0"
                        set /a ERRORS+=1
                        <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - ERROR: spatial-media fallback failed"
                        echo.
                    )
                )
            )
        )

        if "!PIPELINE_OK!"=="1" (
            :: Copy dates and static GPS tags from the original source.
            exiftool -overwrite_original -TagsFromFile "!SRC360_PATH!" "-GPS*" "-CreateDate" "-ModifyDate" "-TrackCreateDate" "-TrackModifyDate" "-MediaCreateDate" "-MediaModifyDate" "!TEMP_OUT!" >nul 2>&1

            :: Recover the first valid GPS sample if the camera started recording
            :: before GPS lock (common with Quick Capture).
            set "HAS_GPS="
            for /f "tokens=*" %%G in ('exiftool -GPSLatitude -n "!TEMP_OUT!" 2^>nul') do set "HAS_GPS=%%G"

            set "TRY_TELEMETRY=0"
            if not defined HAS_GPS set "TRY_TELEMETRY=1"
            echo !HAS_GPS! | findstr /C:": 0" >nul && set "TRY_TELEMETRY=1"

            if "!TRY_TELEMETRY!"=="0" (
                exiftool -overwrite_original "-Keys:GPSCoordinates<$XMP:GPSLatitude# $XMP:GPSLongitude# $XMP:GPSAltitude#" "-UserData:GPSCoordinates<$XMP:GPSLatitude# $XMP:GPSLongitude# $XMP:GPSAltitude#" "!TEMP_OUT!" >nul 2>&1
                if errorlevel 1 (
                    exiftool -overwrite_original "-Keys:GPSCoordinates<$XMP:GPSLatitude# $XMP:GPSLongitude#" "-UserData:GPSCoordinates<$XMP:GPSLatitude# $XMP:GPSLongitude#" "!TEMP_OUT!" >nul 2>&1
                )
            )

            if "!TRY_TELEMETRY!"=="1" (
                for /f "tokens=1,2,3 delims=," %%A in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "$gps = exiftool -ee3 -n -p '$GPSLatitude,$GPSLongitude,$GPSAltitude' '!SRC360_PATH!' 2>$null ^| ForEach-Object { $p = $_.Split(','); if ($p.Count -ge 2 -and $p[0] -ne '0' -and $p[1] -ne '0' -and $p[0] -ne '' -and $p[1] -ne '') { $_; break } } ^| Select-Object -First 1; if ($gps) { $gps }"') do (
                    set "LAT=%%A"
                    set "LON=%%B"
                    set "ALT=%%C"
                    if "!ALT!"=="" set "ALT=0"
                    if not "!LAT!"=="" (
                        exiftool -overwrite_original -Keys:GPSCoordinates="!LAT! !LON! !ALT!" -UserData:GPSCoordinates="!LAT! !LON! !ALT!" -GPSLatitude="!LAT!" -GPSLongitude="!LON!" -GPSAltitude="!ALT!" "!TEMP_OUT!" >nul 2>&1
                    )
                )
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
                exiftool -overwrite_original -Make="GoPro" -Model="GoPro MAX2" "-UserComment=!EXPOSURE_INFO!" "-Description=!EXPOSURE_INFO!" "!TEMP_OUT!" >nul 2>&1
            ) else (
                exiftool -overwrite_original -Make="GoPro" -Model="GoPro MAX2" "!TEMP_OUT!" >nul 2>&1
            )

            :: Final safety gate. The primary video must retain its codec,
            :: resolution, frame rate, frame count/duration and 360 projection.
            <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Verifying integrity..."
            set "VERIFY_RESULT="
            for /f "tokens=*" %%V in ('powershell -NoProfile -ExecutionPolicy Bypass -File "!VERIFY_SCRIPT!" -Reference "!MP4_PATH!" -Candidate "!TEMP_OUT!" -RequireSpherical 2^>^&1') do set "VERIFY_RESULT=%%V"
            echo(!VERIFY_RESULT! | findstr /B /C:"OK:" >nul
            if errorlevel 1 (
                set "PIPELINE_OK=0"
                set /a ERRORS+=1
                set /a NOT360+=1
                echo.
                echo   !VERIFY_RESULT!
                echo   Original render preserved: !MP4_PATH!
            )

            if "!PIPELINE_OK!"=="1" if "!USED_GPMF!"=="1" (
                set "FINAL_GPMF="
                for /f "tokens=*" %%G in ('ffprobe -v error -select_streams d -show_entries stream^=codec_tag_string -of csv^=p^=0 "!TEMP_OUT!" 2^>nul ^| findstr /I "gpmd"') do set "FINAL_GPMF=1"
                if not defined FINAL_GPMF (
                    set "PIPELINE_OK=0"
                    set /a ERRORS+=1
                    echo.
                    echo   ERROR: final file lost the gpmd telemetry stream.
                    echo   Original render preserved: !MP4_PATH!
                )
            )
        )

        if "!PIPELINE_OK!"=="1" (
            move /y "!TEMP_OUT!" "!OUTPUT_DIR!\!MP4_FILE!" >nul 2>&1
            if errorlevel 1 (
                set /a ERRORS+=1
                echo.
                echo   ERROR: Could not move !MP4_FILE! to output folder.
            ) else (
                set /a SUCCESS+=1
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - OK"
                echo.

                del /f /q "!MP4_PATH!" >nul 2>&1
                for %%D in ("!PLAYER_DIR!\!MP4_NAME!.*") do del /f /q "%%D" >nul 2>&1
            )
        ) else (
            if exist "!TEMP_OUT!" del /f /q "!TEMP_OUT!" >nul 2>&1
        )

        if exist "!TEMP_FILE!" del /f /q "!TEMP_FILE!" >nul 2>&1
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
echo   Spatial fallbacks:   !SPATIAL_FALLBACKS!
echo   Verification failed: !NOT360!
echo.
echo   Output folder: %OUTPUT_DIR%
echo.
echo ============================================================================
echo.

endlocal
