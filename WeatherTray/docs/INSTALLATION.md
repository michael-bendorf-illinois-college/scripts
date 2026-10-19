# Install and run WeatherTray v1.6.0

## Before you begin

WeatherTray is intended for **Windows 10/11 and Windows PowerShell 5.1**. It relies on Windows Forms, System.Drawing, NotifyIcon, and an interactive desktop; it is not a cross-platform utility.

No installer, administrator privileges, NuGet package, or external PowerShell module is required. Internet access is required for actual weather data.

## 1. Get the source

1. Use **Code → Download ZIP** on the GitHub repository or clone it with Git.
2. Extract the files.
3. Locate the **WeatherTray** directory containing WeatherTray.ps1.
4. Move/copy that whole folder to a long-lived location such as:

~~~text
C:\Tools\WeatherTray\
    WeatherTray.ps1
    README.md
    LICENSE
    CHANGELOG.md
    docs\
~~~

Keep the folder in place after creating a startup task. Moving it requires updating the task's script path.

## 2. Open the correct PowerShell

Open **Windows PowerShell** (not PowerShell 7), as the regular desktop user who should see the weather icons. If uncertain:

~~~powershell
$PSVersionTable.PSVersion
~~~

A major version of **5** is expected. Do not run the script from a non-interactive service, SYSTEM account, or a scheduled task configured to run without a signed-in user.

## 3. Run WeatherTray

From Windows PowerShell, adjust the example path:

~~~powershell
& "C:\Tools\WeatherTray\WeatherTray.ps1"
~~~

If your execution policy blocks unsigned scripts, consult your organizational policy. On a personally controlled system, one **process-scoped** alternative is:

~~~powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "C:\Tools\WeatherTray\WeatherTray.ps1"
~~~

The above bypass affects only that new PowerShell process; do not use it to defeat an organization-managed policy. Another alternative is to review/unblock a trusted downloaded file with **Unblock-File** before running it.

WeatherTray remains running as a tray application; the PowerShell process does not exit until you choose **Exit** from the tray menu.

## 4. Configure and verify

1. Look near the clock or in the **Show hidden icons** overflow for two icons: a temperature and a condition symbol.
2. Right-click either → **Settings...**.
3. Enter a display label and precise decimal latitude/longitude (see [configuration](CONFIGURATION.md)).
4. Save; a weather refresh should follow.
5. Left-click for a detailed notification. Use **Refresh now** from the right-click menu to refresh weather and NWS data immediately.
6. Use **Open NWS forecast / alerts** to check the browser destination.
7. Confirm the local WeatherTray.log was created under %LOCALAPPDATA%\WeatherTray.

The default approximate Carlinville sample is intentionally not a precise home address.

## 5. Set up automatic login startup (optional)

See [AUTOSTART.md](AUTOSTART.md) for the recommended **Task Scheduler → At log on** approach. Task setup is user-specific and was not contained in the uploaded source archive.

## Updating an existing installation

1. Exit WeatherTray using its tray menu.
2. Preserve your local preferences in **%LOCALAPPDATA%\WeatherTray**. They are **not** normally stored beside WeatherTray.ps1.
3. Replace WeatherTray.ps1 (and optionally the documentation) in the installed script folder.
4. Keep the script path unchanged if an existing logon task points to it.
5. Relaunch or run the task and confirm the log reports **v1.6.0**.

The script uses a per-session mutex to prevent two copies from running concurrently. If a newly launched copy exits immediately, first verify whether the original instance is still active.

## Removing WeatherTray

- Exit the program.
- Disable/delete the WeatherTray logon task if you configured one.
- Remove the program folder when no longer needed.
- If you wish to remove saved preferences, alert history, and logs as well, remove **%LOCALAPPDATA%\WeatherTray** after confirming you no longer need the data.

No Windows service or system-wide registration is performed by the script.
