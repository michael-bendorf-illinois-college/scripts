# WeatherTray

<small>Version **1.6.0** · Windows PowerShell 5.1 · Windows notification-area weather utility</small>

WeatherTray displays local outdoor conditions in the Windows system tray. It draws a large **temperature icon** plus a companion **weather-condition icon**, shows richer weather details on click, and highlights official National Weather Service watches and warnings.

Weather conditions are obtained from **Open-Meteo**, which selects weather model data for your configured coordinates. Active watches and warnings are obtained separately from **NOAA/National Weather Service (NWS)**. These sources are deliberately distinct: a model-derived current temperature is not an airport-station observation.

## Features

- Large white temperature digits on a transparent tray icon, automatically scaled for two- or three-digit values.
- Separate condition icon (sun, clouds, rain, snow, storm, fog, wind, or thermometer), rendered using Windows' Segoe UI Emoji font.
- **!** before the temperature when an applicable active NWS watch or warning is detected.
- Left-click either tray icon for a compact notification with current temperature, apparent/feels-like temperature, weather conditions, wind and gusts, relative humidity, estimated dew point, pressure, visibility, today's high/low, and model time as available.
- Right-click for current status, data-source details, last update, active-alert count, Settings, Refresh now, an NWS forecast/alerts link, and Exit.
- User-configurable **location label** and **decimal latitude,longitude** in Settings.
- New-watch/warning notifications, with a persisted bounded list of previously notified alert IDs to reduce repeat banners.
- Weather and alert refresh every **15 minutes**, plus manual refresh.
- Per-user local settings and rotating log files; prevents duplicate instances in one Windows user session.
- No installer, external PowerShell modules, API keys for the default endpoints, or administrator privileges required.

## Requirements

- Windows 10 or Windows 11 desktop, with an **interactive signed-in user session** and Windows notification area.
- **Windows PowerShell 5.1** (the built-in powershell.exe), .NET Framework Windows Forms and System.Drawing.
- TLS 1.2 HTTPS access to api.open-meteo.com, api.weather.gov, and optionally forecast.weather.gov when opening the forecast.
- A U.S. location for meaningful NWS watch/warning data. Open-Meteo conditions can work outside the U.S., but NWS alerts do not cover other countries.

This is not designed as a service, headless scheduled task, or PowerShell 7 cross-platform process.

## Quick start

1. Download or clone this repository.
2. Copy the **WeatherTray** folder to a stable local directory, for example C:\Tools\WeatherTray.
3. Open **Windows PowerShell 5.1** as your regular Windows user.
4. Run the script (adjust the path):

~~~powershell
& "C:\Tools\WeatherTray\WeatherTray.ps1"
~~~

5. Find the new temperature and condition icons in the Windows notification area. They may initially appear behind Windows' **Show hidden icons** arrow.
6. Right-click either icon → **Settings...** and provide your location name and coordinates. Choose **Save** to refresh.

See the [installation guide](docs/INSTALLATION.md) for execution-policy guidance, updating, and verification.

## Location settings

The Settings dialog accepts **decimal latitude,longitude**, separated by a comma. Latitude comes first; west longitudes use a minus sign.

~~~text
39.280,-89.880
~~~

The example points only approximately to **Carlinville, Illinois**. It is a *town-level example*, not a precise home or office location. The script intentionally ships with an approximate public default; choose your own exact coordinates privately after installation.

| Valid | Invalid |
| --- | --- |
| 39.280,-89.880 | 39°16'58"N 89°53'28"W |
| 41.8781,-87.6298 | 39.280 -89.880 |
| -33.8688,151.2093 | Carlinville, IL |

Valid latitude is from -90 to 90, and longitude from -180 to 180. The dialog rejects degree/minute/second notation and hemisphere letters. See [configuration details](docs/CONFIGURATION.md).

## Tray controls

| Action | Result |
| --- | --- |
| Left-click either icon | Shows weather details in a Windows notification/balloon |
| Right-click either icon | Opens shared context menu |
| **Settings...** | Change location label and coordinates, persist settings, refresh |
| **Refresh now** | Query both sources immediately |
| **Open NWS forecast / alerts** | Opens forecast.weather.gov for your configured location |
| **Exit** | Stops refresh timer and removes both icons |

The left icon is a temperature rendered from Open-Meteo. The companion condition icon is also drawn locally. Colors/emoji appearance depend on Windows' rendering capabilities.

**Multiple-monitor note:** Windows and third-party taskbar utilities (including DisplayFusion) control which notification icons are replicated across taskbars. WeatherTray creates two normal Windows NotifyIcon objects; it cannot force each monitor's taskbar to duplicate both.

## Start automatically on sign-in

A [Windows Task Scheduler logon task](docs/AUTOSTART.md) is a convenient way to start WeatherTray without manually opening a PowerShell window. **Use “Run only when user is logged on”** so the tray UI has access to the interactive desktop. No task definition was included in the supplied archive, so the guide describes how to create or verify your own task. Merely installing the source does not create a task.

## Data sources and API-use terms

| Provider | Used for | Request characteristics |
| --- | --- | --- |
| [Open-Meteo Forecast API](https://open-meteo.com/en/docs) | Current model temperature/conditions, wind, pressure, visibility, and daily high/low | HTTPS GET to api.open-meteo.com, coordinates in query parameters |
| [NWS API](https://www.weather.gov/documentation/services-web-api) | Active watch/warning information | HTTPS GET to api.weather.gov/alerts/active with a coordinate point |
| [NWS forecast site](https://forecast.weather.gov/) | Forecast and alerts page opened on demand | Browser navigation with coordinates |

**Important distinction:** The MPL 2.0 covers this script, **not** the terms of third-party APIs. Open-Meteo's standard free public API is for **non-commercial use**, subject to rate limits and availability; commercial users must check its current licensing and subscription terms. Open-Meteo weather data is subject to **CC BY 4.0 attribution** conditions. Credit: *Weather data by Open-Meteo.com*. NWS is an independent U.S. government weather service. Consult [Open-Meteo terms](https://open-meteo.com/en/terms) and the [NWS API documentation](https://www.weather.gov/documentation/services-web-api) before large-scale or commercial deployments.

The text-to-emoji mapping and all tray graphics are generated at runtime; no third-party icons or packages are bundled.

## Storage, privacy, and logging

WeatherTray creates a per-user directory:

~~~text
%LOCALAPPDATA%\WeatherTray\
    WeatherTraySettings.json
    WeatherTrayState.json
    WeatherTray.log
    WeatherTray.log.old   (after rollover)
~~~

- **Settings JSON:** location label, exact coordinates, save time.
- **State JSON:** up to 200 already-notified NWS alert identifiers and save time.
- **Log:** timestamps, refresh results, errors, and coordinates; rotated when larger than approximately 1 MiB, keeping one .old copy.
- **Network:** your coordinates are transmitted in HTTPS query parameters to the weather services; the services also see normal network metadata such as your public IP address.
- No account credentials, telemetry service, or analytics library are present.

**Do not publish your local settings, state, or log files.** They may disclose precise location or diagnostic information. This repository deliberately excludes the runtime log supplied with the source ZIP and includes a protective .gitignore.

## Known limitations

- NWS watches/warnings are available only where NWS provides coverage, and service data may be delayed, unavailable, or incomplete.
- Banner notification style and timing depend on Windows notification settings. Notifications can be suppressed by Focus Assist / Do Not Disturb or system policies.
- Open-Meteo provides **model-based** current conditions; it is not guaranteed to match the closest physical weather station.
- Local time shown by the model and tray is based on API response/timezone settings and Windows local time handling.
- WeatherTray runs **while your Windows user session is active**; it does not keep updating if the task has been stopped or the process has exited.
- It is **not an emergency alerting device**. Check [weather.gov](https://www.weather.gov/) or authorized alert channels for safety-critical decisions.

## Documentation

- [Installation and manual startup](docs/INSTALLATION.md)
- [Task Scheduler logon startup](docs/AUTOSTART.md)
- [Settings and state files](docs/CONFIGURATION.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Developer architecture and verification](docs/DEVELOPMENT.md)
- [Changelog](CHANGELOG.md)

## Development note

This project was developed with assistance from OpenAI's ChatGPT, including support for code development and documentation. Michael Bendorf is responsible for the project's content, release decisions, and ongoing maintenance.

## License

**Mozilla Public License 2.0** — [local LICENSE](LICENSE) · [repository license](../LICENSE).

Copyright © 2026 Michael Bendorf.

You may use, change, and redistribute the program, including commercially, subject to MPL 2.0's file-level source-sharing requirements upon distribution. Private/internal modifications need not be published; sharing helpful improvements voluntarily is encouraged.

The program is provided **as-is**, without a warranty or guaranteed weather warning delivery.
