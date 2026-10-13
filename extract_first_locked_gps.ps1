# extract_first_locked_gps.ps1
# Extracts the first GPS-locked (3D fix) position from GoPro GPMF telemetry.
# Returns two lines:
#   Line 1: lat,lon,alt (decimal, for XMP tags)
#   Line 2: ISO 6709 string (for Keys/UserData GPSCoordinates)
# Usage: powershell -ExecutionPolicy Bypass -File extract_first_locked_gps.ps1 "path\to\file.360"

param(
    [Parameter(Mandatory=$true)]
    [string]$InputFile
)

if (-not (Test-Path -LiteralPath $InputFile)) {
    exit 1
}

# Extract all GPS samples with measure mode from GPMF telemetry
$lines = & exiftool -ee3 -n -p '$GPSMeasureMode,$GPSLatitude,$GPSLongitude,$GPSAltitude' $InputFile 2>$null
if ($LASTEXITCODE -ne 0) { exit 1 }

$culture = [System.Globalization.CultureInfo]::InvariantCulture
$numberStyle = [System.Globalization.NumberStyles]::Float

foreach ($line in $lines) {
    $parts = $line.Split(',')
    if ($parts.Count -ge 4 -and $parts[0] -eq '3') {
        $lat = 0.0
        $lon = 0.0
        $alt = 0.0
        if (-not [double]::TryParse($parts[1], $numberStyle, $culture, [ref]$lat) -or
            -not [double]::TryParse($parts[2], $numberStyle, $culture, [ref]$lon) -or
            ($parts[3] -and -not [double]::TryParse($parts[3], $numberStyle, $culture, [ref]$alt))) {
            continue
        }
        if ([double]::IsNaN($lat) -or [double]::IsInfinity($lat) -or [Math]::Abs($lat) -gt 90 -or
            [double]::IsNaN($lon) -or [double]::IsInfinity($lon) -or [Math]::Abs($lon) -gt 180 -or
            [double]::IsNaN($alt) -or [double]::IsInfinity($alt)) {
            continue
        }

        # Line 1: decimal values for XMP/standard GPS tags
        Write-Output ([string]::Format($culture, '{0},{1},{2}', $lat, $lon, $alt))

        # Line 2: ISO 6709 format for Keys/UserData GPSCoordinates
        # Format: +DD.DDDDD+DDD.DDDDD+AAAA.AAA/
        # NOTE: Google Photos ignores coordinates with more than 5 decimal digits!
        $latSign = if ($lat -ge 0) { "+" } else { "-" }
        $lonSign = if ($lon -ge 0) { "+" } else { "-" }
        $altSign = if ($alt -ge 0) { "+" } else { "-" }
        $latAbs = [Math]::Abs($lat)
        $lonAbs = [Math]::Abs($lon)
        $altAbs = [Math]::Abs($alt)
        $iso6709 = [string]::Format($culture, '{0}{1:00.#####}{2}{3:000.#####}{4}{5:0.###}/',
            $latSign, $latAbs, $lonSign, $lonAbs, $altSign, $altAbs)
        Write-Output $iso6709

        exit 0
    }
}

# No locked GPS found
exit 1
