@echo off
setlocal EnableDelayedExpansion

:: ============================================================================
:: GoPro MAX 360 Metadata Injector
:: Copies GPS/time metadata from .360 files and forces GSpherical tags for
:: Google Photos 360 recognition. Successfully tagged files are moved to Output.
:: ============================================================================

:: Load configuration
call "%~dp0config.bat"

:: Set directories from config (can be overridden with arguments)
set "RENDER_DIR=%RENDER_DIR%"
set "SRC360_DIR=%SOURCE_360_DIR%"
set "OUTPUT_DIR=%OUTPUT_DIR%"
set "PLAYER_DIR=%WATCH_FOLDER_DIR%\Source"

:: Override with arguments if provided
if not "%~1"=="" set "RENDER_DIR=%~1"
if not "%~2"=="" set "SRC360_DIR=%~2"
if not "%~3"=="" set "OUTPUT_DIR=%~3"

:: Get ANSI escape character
for /F %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"

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
    
    :: Progress line (updateable)
    <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] Processing: !MP4_FILE!"
    
    if not exist "!SRC360_PATH!" (
        set /a MISSING+=1
        <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - SKIP: No matching .360"
        echo.
    ) else (
        set "TEMP_OUT=!TEMP!\!MP4_FILE!"
        
        :: Clean up any existing temp file
        if exist "!TEMP_OUT!" del /f "!TEMP_OUT!" >nul 2>&1
        
        :: Copy to temp
        <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Copying..."
        copy /y "!MP4_PATH!" "!TEMP_OUT!" >nul 2>&1
        
        if not exist "!TEMP_OUT!" (
            set /a ERRORS+=1
            <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - ERROR: Copy failed"
            echo.
        ) else (
            :: Copy GPS and time metadata from .360 source FIRST (Adding Make/Model/Exposure)
            <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Copying GPS/Time/Cam details..."
            exiftool -overwrite_original -TagsFromFile "!SRC360_PATH!" "-GPS*" "-CreateDate" "-ModifyDate" "-TrackCreateDate" "-TrackModifyDate" "-MediaCreateDate" "-MediaModifyDate" "-Make" "-Model" "-ExposureTime" "-FNumber" "-ISO" "-ExposureProgram" "-ExposureMode" "-WhiteBalance" "-FocalLength" "!TEMP_OUT!" >nul 2>&1
            
            :: Inject spherical metadata LAST (after GPS/time to avoid XMP corruption)
            <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Injecting 360 tags..."
            exiftool -overwrite_original -XMP-GSpherical:Spherical=true -XMP-GSpherical:Stitched=true -XMP-GSpherical:ProjectionType=equirectangular -XMP-GSpherical:StereoMode=mono -XMP-GPano:UsePanoramaViewer=True "!TEMP_OUT!" >nul 2>&1
            
            if errorlevel 1 (
                set /a ERRORS+=1
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - ERROR: Inject failed"
                echo.
                del /f "!TEMP_OUT!" >nul 2>&1
            ) else (
                
                :: Verify spherical tag
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Verifying..."
                set "SPHERICAL_VAL="
                for /f "tokens=*" %%V in ('exiftool -s3 -XMP-GSpherical:Spherical "!TEMP_OUT!" 2^>nul') do set "SPHERICAL_VAL=%%V"
                
                if /i "!SPHERICAL_VAL!"=="True" (
                    :: Replace original and move to Output
                    move /y "!TEMP_OUT!" "!MP4_PATH!" >nul 2>&1
                    if errorlevel 1 (
                        set /a ERRORS+=1
                        <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - ERROR: Replace failed"
                        echo.
                        del /f "!TEMP_OUT!" >nul 2>&1
                    ) else (
                        move /y "!MP4_PATH!" "!OUTPUT_DIR!\!MP4_FILE!" >nul 2>&1
                        if errorlevel 1 (
                            set /a ERRORS+=1
                            <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - ERROR: Move failed"
                            echo.
                        ) else (
                            set /a SUCCESS+=1
                            <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - OK"
                            echo.
                            
                            :: Delete processed file from GoPro Player folder (checking .mov extension)
                            if exist "!PLAYER_DIR!\!MP4_NAME!.mov" (
                                del "!PLAYER_DIR!\!MP4_NAME!.mov" >nul 2>&1
                                if not exist "!PLAYER_DIR!\!MP4_NAME!.mov" (
                                   echo       - Deleted .mov from GoPro Player folder
                                )
                            )
                        )
                    )
                ) else (
                    set /a NOT360+=1
                    <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - WARNING: Tag not verified"
                    echo.
                    move /y "!TEMP_OUT!" "!MP4_PATH!" >nul 2>&1
                )
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
echo   Total MP4s:       !TOTAL!
echo   Successfully tagged: !SUCCESS!
echo   Errors:           !ERRORS!
echo   Missing .360:     !MISSING!
echo   Not tagged 360:   !NOT360!
echo.
echo   Output folder: %OUTPUT_DIR%
echo.
echo ============================================================================

pause
