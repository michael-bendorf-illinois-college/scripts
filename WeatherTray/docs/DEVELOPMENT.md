# WeatherTray development and verification

**WeatherTray v1.6.0** · Windows PowerShell 5.1 · MPL-2.0 · Copyright © 2026 Michael Bendorf.

The public source derives from the supplied ZIP's internally labeled **v6.0** script. The release adapts the version identifiers, adds copyright/SPDX notices, substitutes an approximate town-level default coordinate, and removes a location-specific alert fallback. Its primary weather, display, and alert logic is unchanged.

## Startup and event flow

1. Configure TLS 1.2; load Windows Forms, System.Drawing, and a tiny native DestroyIcon helper.
2. Acquire **Local\WeatherTray-PowerShell-5.1** mutex to prevent multiple instances in one user session.
3. Set up LOCALAPPDATA storage, loading saved coordinate settings and notified-alert IDs.
4. Build Open-Meteo and NWS URLs from normalized decimal coordinates.
5. Initialize two NotifyIcon objects and one shared context menu.
6. Call Refresh-All, start a 15-minute Windows Forms Timer, enter Application.Run message loop.
7. On Exit, stop/dispose timer, graphics handles, icons, menu, and mutex, then log shutdown.

## Responsibilities

| Function / section | Behavior |
| --- | --- |
| Try-ParseCoordinates | Validate decimal latitude,longitude and normalize using invariant culture |
| Load/Save-WeatherSettings | Read/write per-user JSON for label and coordinates |
| Load/Save-AlertState | Persist up to 200 already-notified NWS alert IDs |
| Write-WeatherLog | Timestamp diagnostics with 1 MiB rollover and one old copy |
| New-TemperatureIcon | Render large Segoe UI digits to transparent GDI+ image |
| Get-ConditionEmoji / New-ConditionEmojiIcon | Map weather description and draw separate condition glyph |
| Set-TrayTemperature / Refresh-TrayIcon | Add/remove a leading ! when active watches/warnings exist |
| Update-ApiUris | Build HTTPS forecast, alerts, and browser URLs |
| Update-Weather | Query weather, calculate derived values, update tray and menu |
| Update-Alerts | Query active NWS alerts, filter watches/warnings, dedupe notifications |
| Show-WeatherBalloon | Show current status and weather details |
| Show-SettingsDialog | Validate and save coordinates, rebuild requests, refresh |
| Refresh-All | Request weather then alerts |
| Context menu / Timer / Application.Run | Interactive UI and recurring work |

## External requests

### Open-Meteo model weather

Endpoint: https://api.open-meteo.com/v1/forecast

Parameters include latitude, longitude, current temperature_2m, relative_humidity_2m, apparent_temperature, weather_code, pressure_msl, visibility, wind_speed_10m, wind_direction_10m, wind_gusts_10m; daily max/min temperature; Fahrenheit/mph output, automatic timezone, and a two-day forecast.

Dew point is computed from temperature and relative humidity within WeatherTray; it is an estimate. Current data is model-based rather than a nearby physical station observation.

### NWS watch/warning lookup

Endpoint: https://api.weather.gov/alerts/active?point=latitude,longitude

The request sends Accept: application/geo+json and a descriptive User-Agent. Update-Alerts only retains events whose names match **watch** or **warning** (case-insensitive), derives stable IDs, and remembers alerted IDs across sessions. The tray's ! cue is based on the *currently active* response; notification banners appear for *new* IDs.

The NWS forecast menu opens forecast.weather.gov/MapClick.php with the same latitude and longitude.

## UI details

- Windows Forms NotifyIcon has a short tooltip length; captions are truncated to 63 characters.
- Icon artwork is generated on transparent 64×64 bitmaps, then scaled by Windows.
- Managed icons are cloned before the native icon handle is destroyed; old icons and GDI resources are explicitly disposed.
- The companion emoji may render differently depending on Windows/Segoe UI Emoji support.
- Notification banners are a best-effort operating-system feature, not guaranteed warnings.
- Third-party taskbars (for example DisplayFusion) determine whether both normal notification icons appear on additional monitors.

## Data and provider terms

This source is under MPL 2.0, but upstream services have independent terms. Open-Meteo's standard public API is **non-commercial** with request limits and CC BY 4.0 data attribution requirements. The NWS API has its own rate limits and User-Agent guidance. A commercial application of this open-source code must arrange compatible API access. See the [Open-Meteo terms](https://open-meteo.com/en/terms) and [NWS API documentation](https://www.weather.gov/documentation/services-web-api).

Do not commit runtime JSON or logs. They can include exact personal coordinates, location labels, alert IDs, and diagnostics. The original ZIP log was deliberately excluded.

## Windows acceptance checklist

- [ ] Windows PowerShell 5.1 parses and launches WeatherTray in an interactive desktop.
- [ ] Two tray icons appear, both context menus and left-click balloons work.
- [ ] Initial and manual refresh show correct model weather and update time.
- [ ] Valid Settings coordinates are saved and reloaded; invalid or DMS inputs are rejected.
- [ ] Changing location uses the new coordinates in both service URLs.
- [ ] A second launch exits rather than creating duplicate icons.
- [ ] Network failures are logged and do not leave the app with broken state.
- [ ] New NWS watch/warning IDs produce warnings and ! cue; repeat IDs are suppressed.
- [ ] Normal alert cessation removes the ! cue on the next check.
- [ ] Log rotation and state saving work under LOCALAPPDATA.
- [ ] Logon task starts WeatherTray visibly; no unnecessary elevation.
- [ ] Exit cleans up both icons and process resources.

**Publishing check:** The ZIP and source were reviewed statically for sensitive data, release markers, and external behavior. The publishing environment did not have Windows PowerShell 5.1 or a graphical Windows notification area, so a live runtime or parser test **was not run**. Do not misinterpret this checklist as completed test results.

## Maintaining the release

Keep the project standalone, preserve MPL source headers, update the version marker/User-Agent/start-stop log text and CHANGELOG together, and test with Windows PowerShell 5.1 after edits. Share useful improvements back voluntarily, including internally developed fixes.

[Back to WeatherTray](../README.md)
