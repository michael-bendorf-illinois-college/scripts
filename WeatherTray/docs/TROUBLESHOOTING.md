# WeatherTray troubleshooting

## First checks

1. Use **Windows PowerShell 5.1** in a signed-in Windows desktop session.
2. Check the **Show hidden icons** area near the clock.
3. Read **%LOCALAPPDATA%\WeatherTray\WeatherTray.log** and WeatherTray.log.old.
4. Choose **Refresh now** from the tray icon's right-click menu.
5. If starting automatically, check **Task Scheduler → History** and **Last Run Result**.

| Symptom | Likely reason | Check or remedy |
| --- | --- | --- |
| No icons at login | Task never launched, noninteractive account, or hidden icons | Logon trigger, “Run only when user is logged on,” Windows icon overflow |
| One icon missing from a secondary monitor | Taskbar replication settings | Check both icons on primary Windows tray; review DisplayFusion |
| PowerShell window remains visible | Startup action missing hidden-window argument | Review **-WindowStyle Hidden** |
| Second launch exits immediately | Existing instance owns single-instance mutex | Exit the existing instance before retrying |
| Temperature stays -- or ! | First weather query has not completed or failed | Connection, TLS 1.2, API status, WeatherTray.log |
| Temperature stays at older value | A refresh failed and last good reading was retained | Tooltip, updated time, log |
| Temperature differs from airport observation | Open-Meteo is model-based | Check coordinates; it is not a station reading |
| Condition emoji appears blank or monochrome | Windows/Segoe UI Emoji rendering variation | Check Windows fonts; other icons may be available |
| No warning banner | No *new* active alert, NWS failure, or Windows Do Not Disturb | NWS site, log, notifications, alert menu |
| Repeat alert after reset | Previously seen alert ID state deleted | Keep WeatherTrayState.json to suppress repeat banners |
| Settings not persisted | User profile or folder write issue | Check LOCALAPPDATA and task account |
| Wrong location | Existing per-user settings override defaults | Open Settings and save correct coordinates |
| Scheduled task “runs” but no icons | Task is in a headless or different user session | Use interactive logon type and correct user |
| NWS link points elsewhere | Incorrect coordinates | Latitude first, negative west longitude |

## Running interactively

Open Windows PowerShell 5.1 and run:

~~~powershell
& "C:\Tools\WeatherTray\WeatherTray.ps1"
~~~

This can show startup errors that are hidden in a scheduled launch. Check the file path, execution policy, local profile directory rights, Windows Forms availability, firewall/proxy, and any endpoint errors.

## Local diagnostic files

~~~text
%LOCALAPPDATA%\WeatherTray\WeatherTray.log
%LOCALAPPDATA%\WeatherTray\WeatherTray.log.old
~~~

Illustrative log format:

~~~text
2026-10-19T11:00:00-05:00  WeatherTray v1.6.0 started.
2026-10-19T11:00:02-05:00  Weather refreshed from Open-Meteo: ...
~~~

The script rotates the log after approximately 1 MiB. **Do not publish raw logs**: they may contain exact location coordinates, alert identifiers, location names, and error details. Redact before reporting an issue.

## Limitations

- NWS data can be delayed, incomplete, or unavailable. WeatherTray is a convenience indicator, **not** the sole source for emergency alerts.
- Open-Meteo's free endpoint has non-commercial-use conditions and rate limits. Check its [current terms](https://open-meteo.com/en/terms).
- Windows controls notification visibility, duration, Do Not Disturb, and whether old-style balloons appear as banners.
- WeatherTray does not repeatedly retry in a rapid loop; wait for the next 15-minute refresh or request one manual refresh.

For startup task troubleshooting, see [AUTOSTART.md](AUTOSTART.md).

[Back to WeatherTray](../README.md)
