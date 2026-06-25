# BatteryMirror

BatteryMirror is a rootless tweak that mirrors the status bar battery inside Control Center's Low Power Mode tile.

## Current behavior

- Hooks the modern Low Power module controller in SpringBoard.
- Embeds a live `_UIBatteryView` inside the Low Power tile.
- Mirrors the real battery percentage and charging state.
- Respects the system `Show Battery Percentage` preference from SpringBoard.
- Includes a simple master enable switch in Settings.

## Notes

The current implementation favors matching the system battery appearance as closely as possible while keeping layout stable inside the compact Control Center tile.
