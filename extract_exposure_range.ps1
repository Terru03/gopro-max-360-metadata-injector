# extract_exposure_range.ps1
# Extracts min/max ISO and shutter speed from GoPro .360 telemetry
# Usage: .\extract_exposure_range.ps1 "path\to\file.360"
# Returns: ISO_MIN ISO_MAX SHUTTER_SLOW SHUTTER_FAST

param([string]$FilePath)

if (-not (Test-Path $FilePath)) {
    Write-Output "ERROR FILE_NOT_FOUND"
    exit 1
}

# Extract ISO speeds using -ee to extract embedded data
$rawOutput = exiftool -ee $FilePath 2>$null | Out-String

# Parse ISO Speeds - collect all numeric values
$isoValues = @()
$isoMatches = [regex]::Matches($rawOutput, 'ISO Speeds\s*:\s*([\d\s]+)')
foreach ($match in $isoMatches) {
    $nums = $match.Groups[1].Value -split '\s+' | Where-Object { $_ -match '^\d+$' }
    foreach ($n in $nums) {
        $isoValues += [int]$n
    }
}

# Parse Exposure Times - collect all 1/xxx values
$shutterDenoms = @()
$shutterMatches = [regex]::Matches($rawOutput, 'Exposure Times\s*:\s*([^\r\n]+)')
foreach ($match in $shutterMatches) {
    $times = [regex]::Matches($match.Groups[1].Value, '1/(\d+)')
    foreach ($t in $times) {
        $shutterDenoms += [int]$t.Groups[1].Value
    }
}

# Calculate min/max
$isoMin = 0
$isoMax = 0
$shutterSlow = ""
$shutterFast = ""

if ($isoValues.Count -gt 0) {
    $isoMin = ($isoValues | Measure-Object -Minimum).Minimum
    $isoMax = ($isoValues | Measure-Object -Maximum).Maximum
}

if ($shutterDenoms.Count -gt 0) {
    # Smaller denominator = slower shutter, larger = faster
    $minDenom = ($shutterDenoms | Measure-Object -Minimum).Minimum
    $maxDenom = ($shutterDenoms | Measure-Object -Maximum).Maximum
    $shutterSlow = "1/$minDenom"
    $shutterFast = "1/$maxDenom"
}

# Format output for injection
# ISO range like "400-800", Shutter range like "1/30-1/120"
if ($isoMin -eq $isoMax) {
    $isoRange = "$isoMin"
}
else {
    $isoRange = "$isoMin-$isoMax"
}

if ($shutterSlow -eq $shutterFast) {
    $shutterRange = "$shutterSlow"
}
else {
    $shutterRange = "$shutterSlow - $shutterFast"
}

Write-Output "$isoRange|$shutterRange"
