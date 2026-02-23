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

if (-not (Test-Path $InputFile)) {
    exit 1
}

# Extract all GPS samples with measure mode from GPMF telemetry
$lines = & exiftool -ee3 -n -p '$GPSMeasureMode,$GPSLatitude,$GPSLongitude,$GPSAltitude' $InputFile 2>$null

foreach ($line in $lines) {
    $parts = $line.Split(',')
    if ($parts.Count -ge 4 -and $parts[0] -eq '3' -and $parts[1] -ne '0' -and $parts[2] -ne '0') {
        $lat = [double]$parts[1]
        $lon = [double]$parts[2]
        $alt = if ($parts[3]) { [double]$parts[3] } else { 0.0 }

        # Line 1: decimal values for XMP/standard GPS tags
        Write-Output "$($parts[1]),$($parts[2]),$alt"

        # Line 2: ISO 6709 format for Keys/UserData GPSCoordinates
        # Format: +DD.DDDDD+DDD.DDDDD+AAAA.AAA/
        # NOTE: Google Photos ignores coordinates with more than 5 decimal digits!
        $latSign = if ($lat -ge 0) { "+" } else { "-" }
        $lonSign = if ($lon -ge 0) { "+" } else { "-" }
        $altSign = if ($alt -ge 0) { "+" } else { "-" }
        $latAbs = [Math]::Abs($lat)
        $lonAbs = [Math]::Abs($lon)
        $altAbs = [Math]::Abs($alt)
        $iso6709 = "{0}{1:0.#####}{2}{3:000.#####}{4}{5:0.###}/" -f $latSign, $latAbs, $lonSign, $lonAbs, $altSign, $altAbs
        Write-Output $iso6709

        exit 0
    }
}

# No locked GPS found
exit 1
