@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ============================================================================
:: GoPro MAX / MAX2 360 Metadata Injector
::
:: - Matches rendered MP4 files with their original .360 source
:: - Finds the GoPro gpmd telemetry stream dynamically
:: - Preserves existing spherical/equirectangular metadata
:: - Uses Google's spatialmedia tool only when 360 metadata is actually missing
:: - Verifies the primary video before deleting the original render
:: - Keeps the console open when launched by double-click so errors stay visible
:: ============================================================================

call "%~dp0config.bat"

set "RENDER_DIR=%RENDER_DIR%"
set "SRC360_DIR=%SOURCE_360_DIR%"
set "OUTPUT_DIR=%OUTPUT_DIR%"
set "PLAYER_DIR=%WATCH_FOLDER_DIR%\Source"
set "SPATIALMEDIA=%~dp0spatialmedia"
set "VERIFY_SCRIPT=%~dp0verify_video_integrity.ps1"
set "GPS_SCRIPT=%~dp0extract_first_locked_gps.ps1"
set "EXPOSURE_SCRIPT=%~dp0extract_exposure_range.ps1"

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

:: --------------------------------------------------------------------------
:: Dependency checks. Do not close immediately on failure: double-click users
:: need to be able to read the error.
:: --------------------------------------------------------------------------
where ffmpeg >nul 2>&1
if errorlevel 1 (
    echo ERROR: ffmpeg is not available in PATH.
    goto :fatal
)

where ffprobe >nul 2>&1
if errorlevel 1 (
    echo ERROR: ffprobe is not available in PATH.
    goto :fatal
)

where exiftool >nul 2>&1
if errorlevel 1 (
    echo ERROR: exiftool is not available in PATH.
    goto :fatal
)

where powershell >nul 2>&1
if errorlevel 1 (
    echo ERROR: PowerShell is not available in PATH.
    goto :fatal
)

if not exist "%VERIFY_SCRIPT%" (
    echo ERROR: verify_video_integrity.ps1 is missing.
    goto :fatal
)

if not exist "%GPS_SCRIPT%" (
    echo ERROR: extract_first_locked_gps.ps1 is missing.
    goto :fatal
)

if not exist "%EXPOSURE_SCRIPT%" (
    echo ERROR: extract_exposure_range.ps1 is missing.
    goto :fatal
)

if not defined RENDER_DIR (
    echo ERROR: RENDER_DIR is not configured.
    goto :fatal
)

if not defined SRC360_DIR (
    echo ERROR: SOURCE_360_DIR is not configured.
    goto :fatal
)

if not defined OUTPUT_DIR (
    echo ERROR: OUTPUT_DIR is not configured.
    goto :fatal
)

if not exist "%RENDER_DIR%" (
    echo ERROR: Render folder does not exist:
    echo   %RENDER_DIR%
    goto :fatal
)

if not exist "%SRC360_DIR%" (
    echo ERROR: Source .360 folder does not exist:
    echo   %SRC360_DIR%
    goto :fatal
)

if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%" >nul 2>&1
if not exist "%OUTPUT_DIR%" (
    echo ERROR: Could not create output folder:
    echo   %OUTPUT_DIR%
    goto :fatal
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

if !TOTAL! EQU 0 (
    echo   No MP4 files found in the render folder.
    goto :summary
)

for /f "delims=" %%F in ('dir /b /s "%RENDER_DIR%\*.mp4" 2^>nul') do (
    set /a PROCESSED+=1
    set "MP4_PATH=%%F"
    set "MP4_NAME=%%~nF"
    set "MP4_FILE=%%~nxF"
    set "SRC360_PATH=!SRC360_DIR!\!MP4_NAME!.360"

    set "PIPELINE_OK=1"
    set "GPMF_STREAM="
    set "USED_GPMF=0"
    set "GPS_DATA="
    set "GPS_ISO6709="
    set "LAT="
    set "LON="
    set "ALT="

    set "TEMP_FILE=!TEMP!\!MP4_NAME!_working.mp4"
    set "TEMP_GPMF=!TEMP!\!MP4_NAME!_gpmf.mp4"
    set "TEMP_OUT=!TEMP!\!MP4_NAME!_360.mp4"

    echo [!PROCESSED!/!TOTAL!] !MP4_FILE!

    if not exist "!SRC360_PATH!" (
        set /a MISSING+=1
        echo   SKIP: No matching source: !SRC360_PATH!
    ) else (
        if exist "!TEMP_FILE!" del /f /q "!TEMP_FILE!" >nul 2>&1
        if exist "!TEMP_GPMF!" del /f /q "!TEMP_GPMF!" >nul 2>&1
        if exist "!TEMP_OUT!" del /f /q "!TEMP_OUT!" >nul 2>&1

        echo   Copying render...
        copy /y "!MP4_PATH!" "!TEMP_FILE!" >nul 2>&1
        if not exist "!TEMP_FILE!" (
            set "PIPELINE_OK=0"
            set /a ERRORS+=1
            echo   ERROR: Could not copy render to temporary working file.
        )

        :: Extract the first valid GPS lock up front. This is optional metadata;
        :: failure here does not invalidate the video itself.
        if "!PIPELINE_OK!"=="1" (
            set "GPS_LINE=0"
            for /f "tokens=*" %%G in ('powershell -NoProfile -ExecutionPolicy Bypass -File "!GPS_SCRIPT!" "!SRC360_PATH!" 2^>nul') do (
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
        )

        :: Find gpmd by codec tag. Never assume a fixed stream index because
        :: normal video, timelapse and other recording modes can differ.
        if "!PIPELINE_OK!"=="1" (
            for /f "tokens=1,2 delims=," %%A in ('ffprobe -v error -select_streams d -show_entries stream^=index^,codec_tag_string -of csv^=p^=0 "!SRC360_PATH!" 2^>nul') do (
                if /I "%%B"=="gpmd" if not defined GPMF_STREAM set "GPMF_STREAM=%%A"
            )

            if defined GPMF_STREAM (
                set "USED_GPMF=1"
                echo   Injecting GPMF telemetry from stream !GPMF_STREAM!...

                :: -shortest prevents a longer source telemetry track from
                :: extending the rendered MP4 duration.
                ffmpeg -y -v error -i "!TEMP_FILE!" -i "!SRC360_PATH!" -map 0 -map 1:!GPMF_STREAM! -map_metadata 0 -c copy -shortest "!TEMP_GPMF!"

                if errorlevel 1 (
                    set "PIPELINE_OK=0"
                    set /a ERRORS+=1
                    echo   ERROR: FFmpeg GPMF injection failed.
                ) else if not exist "!TEMP_GPMF!" (
                    set "PIPELINE_OK=0"
                    set /a ERRORS+=1
                    echo   ERROR: FFmpeg did not create the GPMF output file.
                ) else (
                    move /y "!TEMP_GPMF!" "!TEMP_FILE!" >nul 2>&1
                )
            ) else (
                set /a NO_GPMF+=1
                echo   WARNING: No gpmd telemetry stream found. Continuing without GPMF.
            )
        )

        :: Check whether the GoPro Player render already contains Spherical
        :: Video V2 equirectangular metadata. If yes, preserve it exactly.
        if "!PIPELINE_OK!"=="1" (
            set "HAS_SPHERICAL="
            for /f "tokens=*" %%S in ('ffprobe -v error -select_streams v:0 -show_entries stream_side_data^=projection -of default^=nw^=1:nk^=1 "!TEMP_FILE!" 2^>nul ^| findstr /I /C:"equirectangular"') do set "HAS_SPHERICAL=1"

            if defined HAS_SPHERICAL (
                echo   Existing equirectangular 360 metadata found. Preserving it.
                move /y "!TEMP_FILE!" "!TEMP_OUT!" >nul 2>&1
            ) else (
                set /a SPATIAL_FALLBACKS+=1
                echo   360 metadata missing. Using spatialmedia fallback...

                if not exist "!SPATIALMEDIA!" (
                    set "PIPELINE_OK=0"
                    set /a ERRORS+=1
                    echo   ERROR: spatialmedia fallback is missing: !SPATIALMEDIA!
                ) else (
                    python "!SPATIALMEDIA!" -i "!TEMP_FILE!" "!TEMP_OUT!"
                    if errorlevel 1 (
                        set "PIPELINE_OK=0"
                        set /a ERRORS+=1
                        echo   ERROR: spatialmedia failed.
                    ) else if not exist "!TEMP_OUT!" (
                        set "PIPELINE_OK=0"
                        set /a ERRORS+=1
                        echo   ERROR: spatialmedia did not create an output file.
                    )
                )
            )
        )

        :: Add dates, GPS, camera information and exposure summary.
        if "!PIPELINE_OK!"=="1" (
            echo   Writing metadata...
            exiftool -overwrite_original -TagsFromFile "!SRC360_PATH!" "-CreateDate" "-ModifyDate" "-TrackCreateDate" "-TrackModifyDate" "-MediaCreateDate" "-MediaModifyDate" "!TEMP_OUT!" >nul 2>&1

            if defined GPS_DATA (
                exiftool -overwrite_original -n "-Keys:GPSCoordinates=!GPS_ISO6709!" "-UserData:GPSCoordinates=!GPS_ISO6709!" -XMP-exif:GPSLatitude="!LAT!" -XMP-exif:GPSLongitude="!LON!" -XMP-exif:GPSAltitude="!ALT!" -XMP-exif:GPSAltitudeRef=0 "!TEMP_OUT!" >nul 2>&1
                exiftool -overwrite_original "-UserData:LocationInformation=" "!TEMP_OUT!" >nul 2>&1
            )

            set "EXPOSURE_DATA="
            for /f "tokens=*" %%E in ('powershell -NoProfile -ExecutionPolicy Bypass -File "!EXPOSURE_SCRIPT!" "!SRC360_PATH!" 2^>nul') do set "EXPOSURE_DATA=%%E"

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
        )

        :: Final integrity gate. The original render is never deleted unless
        :: the main video still matches and spherical metadata is present.
        if "!PIPELINE_OK!"=="1" (
            echo   Verifying video integrity...
            set "VERIFY_RESULT="
            for /f "tokens=*" %%V in ('powershell -NoProfile -ExecutionPolicy Bypass -File "!VERIFY_SCRIPT!" -Reference "!MP4_PATH!" -Candidate "!TEMP_OUT!" -RequireSpherical 2^>^&1') do set "VERIFY_RESULT=%%V"

            echo   !VERIFY_RESULT!
            echo(!VERIFY_RESULT! | findstr /B /C:"OK:" >nul
            if errorlevel 1 (
                set "PIPELINE_OK=0"
                set /a ERRORS+=1
                set /a NOT360+=1
                echo   ERROR: Integrity verification failed. Original render preserved.
            )
        )

        if "!PIPELINE_OK!"=="1" if "!USED_GPMF!"=="1" (
            set "FINAL_GPMF="
            for /f "tokens=*" %%G in ('ffprobe -v error -select_streams d -show_entries stream^=codec_tag_string -of csv^=p^=0 "!TEMP_OUT!" 2^>nul ^| findstr /I /C:"gpmd"') do set "FINAL_GPMF=1"

            if not defined FINAL_GPMF (
                set "PIPELINE_OK=0"
                set /a ERRORS+=1
                echo   ERROR: Final file lost its gpmd telemetry stream. Original preserved.
            )
        )

        if "!PIPELINE_OK!"=="1" (
            move /y "!TEMP_OUT!" "!OUTPUT_DIR!\!MP4_FILE!" >nul 2>&1
            if errorlevel 1 (
                set /a ERRORS+=1
                echo   ERROR: Could not move final file to output folder.
            ) else (
                set /a SUCCESS+=1
                echo   OK: !OUTPUT_DIR!\!MP4_FILE!

                del /f /q "!MP4_PATH!" >nul 2>&1
                if defined PLAYER_DIR (
                    for %%D in ("!PLAYER_DIR!\!MP4_NAME!.*") do del /f /q "%%D" >nul 2>&1
                )
            )
        ) else (
            if exist "!TEMP_OUT!" del /f /q "!TEMP_OUT!" >nul 2>&1
        )

        if exist "!TEMP_FILE!" del /f /q "!TEMP_FILE!" >nul 2>&1
        if exist "!TEMP_GPMF!" del /f /q "!TEMP_GPMF!" >nul 2>&1

        echo.
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

if /I not "%GOPRO_NO_PAUSE%"=="1" pause

set "FINAL_EXIT=0"
if !ERRORS! GTR 0 set "FINAL_EXIT=1"
endlocal & exit /b %FINAL_EXIT%

:fatal
echo.
echo The injector cannot continue. Fix the error above and run it again.
echo.
if /I not "%GOPRO_NO_PAUSE%"=="1" pause
endlocal
exit /b 1
