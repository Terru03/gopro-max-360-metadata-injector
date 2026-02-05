@echo off
setlocal EnableDelayedExpansion

:: ============================================================================
:: GoPro MAX 360 Photo Injector
:: Matches .jpg in "4 - GoPro Player Exports" with .36P in "1 - .360 files"
:: Injects Google Photos 360 metadata and moves to "3 - Output"
:: ============================================================================

:: Load configuration
call "%~dp0config.bat"

:: Set directories from config (can be overridden with arguments)
set "V_SOURCE_DIR=%PHOTO_EXPORT_DIR%"
set "METADATA_DIR=%SOURCE_360_DIR%"
set "OUTPUT_DIR=%OUTPUT_DIR%"

:: Override with arguments if provided
if not "%~1"=="" set "V_SOURCE_DIR=%~1"
if not "%~2"=="" set "METADATA_DIR=%~2"
if not "%~3"=="" set "OUTPUT_DIR=%~3"

:: Get ANSI escape character
for /F %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"

:: Counters
set /a PROCESSED=0
set /a ERRORS=0
set /a MISSING=0
set /a NOT360=0
set /a SUCCESS=0

:: Count total JPG files
set /a TOTAL=0
for /f "delims=" %%F in ('dir /b /s "%V_SOURCE_DIR%\*.jpg" 2^>nul') do set /a TOTAL+=1

echo.
echo ============================================================================
echo   GoPro MAX 360 Photo Injector
echo ============================================================================
echo.
echo   Source Folder:   %V_SOURCE_DIR%
echo   Metadata Source: %METADATA_DIR% (.36P)
echo   Output Folder:   %OUTPUT_DIR%
echo   Total JPGs:      !TOTAL!
echo.
echo ============================================================================
echo.

:: Create output directory if it doesn't exist
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

:: Exit early if no files found
if !TOTAL! EQU 0 (
    echo   No JPG files found in source folder.
    echo.
    goto :summary
)

:: Process each JPG in Source folder
for /f "delims=" %%F in ('dir /b /s "%V_SOURCE_DIR%\*.jpg" 2^>nul') do (
    set /a PROCESSED+=1
    set "JPG_PATH=%%F"
    set "JPG_NAME=%%~nF"
    set "JPG_FILE=%%~nxF"
    set "SRC36P_PATH=!METADATA_DIR!\!JPG_NAME!.36P"
    
    :: Progress line (updateable)
    <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] Processing: !JPG_FILE!"
    
    if not exist "!SRC36P_PATH!" (
        set /a MISSING+=1
        <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !JPG_FILE! - SKIP: No matching .36P"
        echo.
    ) else (
        set "TEMP_OUT=!TEMP!\!JPG_FILE!"
        
        :: Clean up any existing temp file
        if exist "!TEMP_OUT!" del /f "!TEMP_OUT!" >nul 2>&1
        
        :: Copy to temp
        <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !JPG_FILE! - Copying..."
        copy /y "!JPG_PATH!" "!TEMP_OUT!" >nul 2>&1
        
        if not exist "!TEMP_OUT!" (
            set /a ERRORS+=1
            <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !JPG_FILE! - ERROR: Copy failed"
            echo.
        ) else (
            :: Step 0: Strip all existing XMP metadata to remove conflicting GoPro tags
            <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !JPG_FILE! - Cleaning XMP..."
            exiftool -overwrite_original -XMP:all= "!TEMP_OUT!" >nul 2>&1

            :: Step 1: Copy GPS, time, and camera settings from .36P source (Re-copying ensures we have what we need)
            <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !JPG_FILE! - Copying GPS/Time/Cam details..."
            exiftool -overwrite_original -TagsFromFile "!SRC36P_PATH!" "-GPS*" "-CreateDate" "-ModifyDate" "-DateTimeOriginal" "-Make" "-Model" "-ExposureTime" "-FNumber" "-ISO" "-ExposureProgram" "-ExposureMode" "-WhiteBalance" "-FocalLength" "!TEMP_OUT!" >nul 2>&1
            
            :: Step 2: Inject GPano metadata LAST
            :: Strongest Robust Method: Explicit FullPano dimensions + Explicit Pose. 
            :: Adding PoseHeadingDegrees=0 sometimes fixes device-specific texture alignment bugs (S24 Ultra).
            <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !JPG_FILE! - Injecting 360 tags..."
            exiftool -overwrite_original -XMP-GPano:UsePanoramaViewer=True -XMP-GPano:ProjectionType=equirectangular "-XMP-GPano:CroppedAreaImageWidthPixels<ImageWidth" "-XMP-GPano:CroppedAreaImageHeightPixels<ImageHeight" "-XMP-GPano:FullPanoWidthPixels<ImageWidth" "-XMP-GPano:FullPanoHeightPixels<ImageHeight" -XMP-GPano:CroppedAreaLeftPixels=0 -XMP-GPano:CroppedAreaTopPixels=0 -XMP-GPano:PoseHeadingDegrees=0 -XMP-GPano:PosePitchDegrees=0 -XMP-GPano:PoseRollDegrees=0 "!TEMP_OUT!" >nul 2>&1
            
            if errorlevel 1 (
                set /a ERRORS+=1
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !JPG_FILE! - ERROR: Inject failed"
                echo.
                del /f "!TEMP_OUT!" >nul 2>&1
            ) else (
                :: Verify GPano tag
                <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !JPG_FILE! - Verifying..."
                set "PANO_VAL="
                for /f "tokens=*" %%V in ('exiftool -s3 -XMP-GPano:UsePanoramaViewer "!TEMP_OUT!" 2^>nul') do set "PANO_VAL=%%V"
                
                if /i "!PANO_VAL!"=="True" (
                    :: Move to Output folder (renaming implies replacing if exists)
                    move /y "!TEMP_OUT!" "!OUTPUT_DIR!\!JPG_FILE!" >nul 2>&1
                    if errorlevel 1 (
                        set /a ERRORS+=1
                        <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !JPG_FILE! - ERROR: Move to Output failed"
                        echo.
                    ) else (
                        set /a SUCCESS+=1
                        <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !JPG_FILE! - OK"
                        echo.
                        
                        :: Success: Delete original from Source folder
                        :: Success: Delete original from Source folder
                        del "!JPG_PATH!" >nul 2>&1
                    )
                ) else (
                    set /a NOT360+=1
                    <nul set /p "=!ESC![2K!ESC![G[!PROCESSED!/!TOTAL!] !JPG_FILE! - WARNING: Tag not verified"
                    echo.
                    :: Move temp to output anyway, tagged as warning
                    move /y "!TEMP_OUT!" "!OUTPUT_DIR!\!JPG_FILE!" >nul 2>&1
                )
            )
        )
    )
    echo.
)

:summary
echo.
echo.
echo ============================================================================
echo   SUMMARY
echo ============================================================================
echo.
echo   Total JPGs:       !TOTAL!
echo   Success:          !SUCCESS!
echo   Errors:           !ERRORS!
echo   Missing .36P:     !MISSING!
echo   Not tagged 360:   !NOT360!
echo.
echo   Output folder: %OUTPUT_DIR%
echo.
echo ============================================================================

pause
