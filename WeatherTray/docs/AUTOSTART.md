# Launch WeatherTray at Windows sign-in

This guide reproduces the intent of the existing owner-created Windows logon job. **The supplied ZIP contained only WeatherTray.ps1 and a historical runtime log**—no Task Scheduler task XML or exported task definition. These steps describe a suitable configuration without claiming to reproduce unseen settings exactly.

The utility requires a visible notification area in an **interactive user session**. Task Scheduler can launch it automatically whenever that user signs in.

## Recommended Task Scheduler configuration

1. Press **Win+R**, type **taskschd.msc**, and open **Task Scheduler**.
2. Choose **Create Task...** (the full dialog, not *Create Basic Task*).
3. **General**
   - Name: **WeatherTray** (or another descriptive name).
   - Choose **Run only when user is logged on**.
   - Use the Windows user who will see the tray icons.
   - Leave **Run with highest privileges** **unchecked**. Administrator access is not necessary.
4. **Triggers → New...**
   - Begin task: **At log on**.
   - Choose your specific user account.
   - Enable the trigger.
5. **Actions → New...**
   - Action: **Start a program**.
   - Program/script:

~~~text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
~~~

   - Add arguments (adjust the actual script location):

~~~text
-NoProfile -STA -WindowStyle Hidden -File "C:\Tools\WeatherTray\WeatherTray.ps1"
~~~

   - Start in (optional; path **without quotes**):

~~~text
C:\Tools\WeatherTray
~~~

6. **Conditions**
   - On laptops, review **Start the task only if the computer is on AC power** and **Stop if the computer switches to battery power**; disable those restrictions if you want continuous tray operation while on battery.
   - Do not require a network connection unless you deliberately want that behavior; a temporary weather-service outage is handled by the script.
7. **Settings**
   - Allow task to be run on demand.
   - If already running: **Do not start a new instance**.
   - Disable any **Stop the task if it runs longer than...** setting, because WeatherTray is intended to remain running.
   - Optionally retry the task if startup fails; do not create rapid restart loops.
8. Save the task.

**Execution-policy note:** If you need the process-scoped policy override discussed in the installation guide, add **-ExecutionPolicy Bypass** to the arguments (between -NoProfile and -STA), subject to your organization's PowerShell policy.

## Test before relying on it

1. Ensure WeatherTray is not already running. Use the tray **Exit** command.
2. In Task Scheduler, select the WeatherTray task and choose **Run**.
3. Confirm both tray icons appear and the context menu responds.
4. Verify that %LOCALAPPDATA%\WeatherTray\WeatherTray.log records a **v1.6.0 started** entry.
5. Sign out and back in to confirm the **At log on** trigger.
6. If no icons are visible, inspect Task Scheduler **History**, **Last Run Result**, and the WeatherTray log. Windows might hide icons under its overflow menu.

## Why these settings matter

| Setting | Reason |
| --- | --- |
| At log on | Starts when your interactive desktop becomes available |
| Run only when user is logged on | Allows NotifyIcon objects and notifications to appear in your user session |
| Do not run with highest privileges | Minimizes unnecessary permissions |
| powershell.exe (5.1), -STA | Runs the Windows Forms program in the intended host and apartment state |
| -WindowStyle Hidden | Avoids leaving a console window visible after startup |
| Do not stop after a fixed duration | Keeps the tray utility alive through the session |
| Stable script path | Prevents a broken scheduled task after folder moves |

## Alternatives

A Startup-folder shortcut to powershell.exe using the same arguments may also work. Task Scheduler usually offers better visibility into the launch result and allows a logon trigger. Only use **one** startup method to avoid duplicate-launch attempts (the script's mutex will ordinarily close a second copy).

## Multi-monitor and DisplayFusion considerations

WeatherTray makes two standard Windows notification-area icons. Windows decides where those icons appear. DisplayFusion and other multi-monitor taskbar tools can replicate some but not all icons. If the condition icon appears only on the primary taskbar, first check the utility's taskbar notification-area options; this does not necessarily mean the second WeatherTray icon failed to launch.

## Do not run headless

**Run whether user is logged on or not**, SYSTEM, service accounts, and remote non-interactive sessions are inappropriate for a program whose purpose is to display tray icons and user notifications.

[Back to WeatherTray](../README.md)
