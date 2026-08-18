param(
    [Parameter(Mandatory = $true)]
    [string]$Reference,

    [Parameter(Mandatory = $true)]
    [string]$Candidate,

    [switch]$RequireSpherical,

    [double]$DurationToleranceSeconds = 0.15
)

$ErrorActionPreference = 'Stop'

function Get-VideoInfo {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "File not found: $Path"
    }

    $jsonText = (& ffprobe -v error -select_streams v:0 `
        -show_entries 'stream=codec_name,width,height,r_frame_rate,duration,nb_frames:stream_side_data' `
        -of json $Path | Out-String)

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($jsonText)) {
        throw "ffprobe failed for: $Path"
    }

    $json = $jsonText | ConvertFrom-Json
    if (-not $json.streams -or $json.streams.Count -lt 1) {
        throw "No primary video stream found in: $Path"
    }

    $stream = $json.streams[0]

    $duration = 0.0
    if (-not [double]::TryParse(
        [string]$stream.duration,
        [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$duration
    )) {
        throw "Could not read video duration from: $Path"
    }

    $frames = $null
    $parsedFrames = 0L
    if ([long]::TryParse([string]$stream.nb_frames, [ref]$parsedFrames)) {
        $frames = $parsedFrames
    }

    $spherical = $false
    if ($stream.side_data_list) {
        foreach ($sideData in $stream.side_data_list) {
            if (([string]$sideData.side_data_type -match 'Spherical') -and
                ([string]$sideData.projection -eq 'equirectangular')) {
                $spherical = $true
                break
            }
        }
    }

    [pscustomobject]@{
        Codec      = [string]$stream.codec_name
        Width      = [int]$stream.width
        Height     = [int]$stream.height
        FrameRate  = [string]$stream.r_frame_rate
        Duration   = $duration
        Frames     = $frames
        Spherical  = $spherical
    }
}

try {
    $referenceInfo = Get-VideoInfo -Path $Reference
    $candidateInfo = Get-VideoInfo -Path $Candidate

    $problems = [System.Collections.Generic.List[string]]::new()

    if ($referenceInfo.Codec -ne $candidateInfo.Codec) {
        $problems.Add("codec changed: $($referenceInfo.Codec) -> $($candidateInfo.Codec)")
    }

    if ($referenceInfo.Width -ne $candidateInfo.Width -or
        $referenceInfo.Height -ne $candidateInfo.Height) {
        $problems.Add("resolution changed: $($referenceInfo.Width)x$($referenceInfo.Height) -> $($candidateInfo.Width)x$($candidateInfo.Height)")
    }

    if ($referenceInfo.FrameRate -ne $candidateInfo.FrameRate) {
        $problems.Add("frame rate changed: $($referenceInfo.FrameRate) -> $($candidateInfo.FrameRate)")
    }

    $durationDifference = [math]::Abs($referenceInfo.Duration - $candidateInfo.Duration)
    if ($durationDifference -gt $DurationToleranceSeconds) {
        $problems.Add(('duration changed by {0:N3}s: {1:N3}s -> {2:N3}s' -f $durationDifference, $referenceInfo.Duration, $candidateInfo.Duration))
    }

    if ($null -ne $referenceInfo.Frames -and $null -ne $candidateInfo.Frames -and
        $referenceInfo.Frames -ne $candidateInfo.Frames) {
        $problems.Add("frame count changed: $($referenceInfo.Frames) -> $($candidateInfo.Frames)")
    }

    if ($RequireSpherical -and -not $candidateInfo.Spherical) {
        $problems.Add('spherical equirectangular metadata is missing')
    }

    if ($problems.Count -gt 0) {
        Write-Output ('FAIL: ' + ($problems -join '; '))
        exit 2
    }

    $frameText = if ($null -ne $candidateInfo.Frames) { "$($candidateInfo.Frames) frames" } else { 'frame count unavailable' }
    $sphericalText = if ($candidateInfo.Spherical) { 'spherical=yes' } else { 'spherical=no' }
    Write-Output ('OK: {0}x{1}, {2}, {3:N3}s, {4}, {5}' -f $candidateInfo.Width, $candidateInfo.Height, $candidateInfo.FrameRate, $candidateInfo.Duration, $frameText, $sphericalText)
    exit 0
}
catch {
    Write-Output ('FAIL: ' + $_.Exception.Message)
    exit 3
}
