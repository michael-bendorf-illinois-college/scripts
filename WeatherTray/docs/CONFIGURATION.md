# WeatherTray configuration and local data

WeatherTray v1.6.0 is configured entirely through its **Settings...** tray menu. There is no external settings server or API token for the default weather endpoints.

## Location

The Settings dialog contains:

1. **Location name** — free-form text used in tray tooltips and notification titles.
2. **Exact coordinates** — a pair of decimal numbers, in **latitude,longitude** order.

Example:

~~~text
39.280,-89.880
~~~

This example is deliberately approximate to the center of Carlinville, Illinois. Replace it with coordinates appropriate for *your own* location in your local Settings dialog; exact house coordinates need not be included in any public source file.

Rules:

- Use a comma to separate the two values; no address text.
- Latitude must be between -90 and 90.
- Longitude must be between -180 and 180.
- West of the prime meridian: **negative longitude**.
- South of the equator: **negative latitude**.
- Decimal dot as separator; no degree, minute, second, or N/W/S/E characters.
- Examples such as 41.8781,-87.6298 are accepted; 41°52'N 87°37'W is rejected.

WeatherTray validates both numbers and stores a normalized representation with at most five decimal places. Pressing **Save** stores the values and immediately refreshes weather and alerts.

## Refresh interval

**15 minutes** by default. This version defines the interval with **RefreshMinutes = 15** in WeatherTray.ps1; it is not editable in the Settings dialog. **Refresh now** bypasses the timer and queries the services on demand.

## Application data

All files below reside in your Windows profile:

~~~text
%LOCALAPPDATA%\WeatherTray\
├── WeatherTraySettings.json
├── WeatherTrayState.json
├── WeatherTray.log
└── WeatherTray.log.old    (created only on log rollover)
~~~

### WeatherTraySettings.json

A human-readable UTF-8 JSON file containing:

| Field | Meaning |
| --- | --- |
| LocationName | The label shown in the tray UI |
| Coordinates | Private exact decimal latitude/longitude |
| SavedAt | Last save time in ISO 8601 format |

If the settings file is absent or unreadable, a publicly safe approximate Carlinville default is used. If the saved coordinates are invalid, the script falls back to its default coordinates. A user-editable Settings dialog remains available.

### WeatherTrayState.json

Tracks previously notified NWS watch/warning IDs and a save timestamp. WeatherTray retains up to 200 IDs, reducing repeat notifications on refresh or restart. IDs correspond to external alerts, not user identities.

Deleting this file while WeatherTray is stopped resets the notification history; ongoing alerts may appear as new the next time the script runs.

### WeatherTray.log and WeatherTray.log.old

A timestamped operational log of starts/stops, weather refreshes, errors, and new alerts. The script rolls over the current log after it exceeds approximately **1 MiB**, retaining one **.old** copy.

**Privacy caution:** logs include coordinates and can include response errors or alert IDs. Do not upload logs or settings publicly without reviewing and redacting them. The ZIP's historical WeatherTray.log is **not included** in this repository.

## Privacy and network requests

- Open-Meteo receives configured latitude and longitude through HTTPS query parameters for model-based current weather and forecast data.
- NWS receives the coordinates in its alert lookup. Opening the NWS forecast also passes coordinates through a browser URL.
- Both providers receive ordinary connection metadata such as IP address; consult their privacy policies.
- WeatherTray does not send configuration to the repository, does not collect analytics, and does not request personal account credentials.

Weather data is refreshed as long as the script runs; it is not a background service independent of your Windows login.

## Reset to defaults

1. Choose **Exit** from the WeatherTray tray menu.
2. Back up your private settings JSON if you might want it later.
3. Remove or rename WeatherTraySettings.json from your local application-data folder.
4. Start WeatherTray again, then reopen Settings to enter the desired location.

For alert notification history reset, similarly remove or rename WeatherTrayState.json while the application is stopped. These steps are optional and affect only files in your own Windows profile.

[Back to WeatherTray](../README.md)
