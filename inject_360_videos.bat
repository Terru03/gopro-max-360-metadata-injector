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
            :: Step 1: Inject spherical metadata using Google's spatial-media tool FIRST
            :: (This creates a new file, so we do this before adding other metadata)
            <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Injecting 360 metadata..."
            python "!SPATIALMEDIA!" -i "!TEMP_FILE!" "!TEMP_OUT!" >nul 2>&1
            
            if not exist "!TEMP_OUT!" (
                set /a ERRORS+=1
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - ERROR: spatial-media failed"
                echo.
                del /f "!TEMP_FILE!" >nul 2>&1
            ) else (
                :: Step 2: Copy GPS and time metadata from .360 source to the OUTPUT file
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Adding GPS/Time metadata..."
                exiftool -overwrite_original -TagsFromFile "!SRC360_PATH!" "-GPS*" "-CreateDate" "-ModifyDate" "-TrackCreateDate" "-TrackModifyDate" "-MediaCreateDate" "-MediaModifyDate" "!TEMP_OUT!" >nul 2>&1
                
                :: Step 3: Set Make and Model (GoPro MAX videos only have "MAX2" in source)
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !MP4_FILE! - Setting camera info..."
                exiftool -overwrite_original -Make="GoPro" -Model="GoPro MAX2" "!TEMP_OUT!" >nul 2>&1
                
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
                        
                        :: Delete original from Render folder
                        del "!MP4_PATH!" >nul 2>&1
                        
                        :: Delete processed file from GoPro Player folder (checking .mov extension)
                        if exist "!PLAYER_DIR!\!MP4_NAME!.mov" (
                            del "!PLAYER_DIR!\!MP4_NAME!.mov" >nul 2>&1
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

pause
