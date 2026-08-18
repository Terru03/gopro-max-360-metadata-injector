# Changelog

## 2026-08-18

### Fixed: GoPro GPMF telemetry reinjection

- Removed the hard-coded assumption that GPMF telemetry is always stream `1:3`.
- Both `inject_360_videos.bat` and `inject_flat_videos.bat` now locate the data stream whose codec tag is `gpmd` dynamically.
- Telemetry is capped to the rendered video's own duration so a longer `.360` telemetry track cannot extend the output container.
- Existing spherical/equirectangular metadata from GoPro Player is preserved instead of rewriting every 360 MP4 with Google's `spatialmedia` tool.
- `spatialmedia` remains available as a fallback only when spherical metadata is actually missing.
- Added `verify_video_integrity.ps1` to compare the primary video codec, resolution, frame rate, duration and frame count before a processed render is accepted.
- 360 output verification also requires spherical equirectangular metadata to remain present.
- When GPMF was injected, the final output is checked to confirm that the `gpmd` data stream survived metadata rewriting.
- Original renders are not deleted when integrity verification fails.

### Root cause

A GoPro MAX2 timelapse `.360` file used stream 2 for `gpmd` telemetry and stream 3 for the second HEVC lens video. The previous `-map 1:3` command therefore injected a full camera video stream instead of telemetry. This could make the final MP4 report the wrong duration and behave as if the main rendered video were corrupted.
