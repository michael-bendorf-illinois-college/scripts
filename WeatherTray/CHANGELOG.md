# WeatherTray changelog

## 1.6.0 — Initial public source release (2026-10-19)

- Published the existing Windows PowerShell 5.1 hybrid weather utility.
- Retained Open-Meteo weather model data plus official NWS watch/warning integration, 15-minute refresh, tray icons, detailed balloons, user configuration, persistent alert IDs, and rotating local logs.
- Standardized the publicly published script header, User-Agent, and startup/shutdown log messages to **1.6.0**. The source ZIP previously labeled this build **6.0**.
- Replaced precise owner-specific example/default coordinates with an **approximate Carlinville town-center example**, while preserving the ability to enter precise private coordinates through Settings.
- Generalized one alert fallback message that mentioned Carlinville explicitly.
- Deliberately excluded WeatherTray.log from source control because runtime logs can contain precise coordinates and user-specific diagnostics.
- Added installation, autostart, configuration, troubleshooting, and development documentation.
- Released the script and documentation under **MPL 2.0**, Copyright © 2026 Michael Bendorf.

**Compatibility:** The public changes above do not alter the primary weather-query and tray-control logic. The behavior of a fresh installation differs only in its approximate default coordinates and corrected generic alert wording. Existing users with saved WeatherTraySettings.json retain their own configured coordinates.

**Verification:** ZIP source and manifest checked, version markers and privacy-sensitive defaults reviewed. A full Windows PowerShell 5.1 parse and interactive notification-area test were **not** run in the publishing environment.

This is the first entry in this repository's WeatherTray release history; earlier private iterations are not represented as separate public Git tags or releases.
