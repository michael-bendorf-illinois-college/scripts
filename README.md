# Scripts

A growing collection of small, practical **quality-of-life enhancement scripts** for everyday computing. Each project is independently usable, documented, and versioned. The collection will expand over time as useful automation and desktop tools are added.

## Projects

| Project | Current version | Platform | Purpose |
| --- | --- | --- | --- |
| [WeatherTray](WeatherTray/) | **1.6.0** | Windows 10/11, Windows PowerShell 5.1 | Display local weather, temperature, conditions, and official NWS watch/warning cues in the Windows notification area |

### WeatherTray

[WeatherTray](WeatherTray/README.md) is a lightweight, long-running desktop utility with no external PowerShell modules. It uses [Open-Meteo](https://open-meteo.com/) for location-based weather conditions and the [National Weather Service](https://www.weather.gov/) for official U.S. watch/warning information.

- **[Install and run](WeatherTray/docs/INSTALLATION.md)**
- **[Set coordinates and preferences](WeatherTray/docs/CONFIGURATION.md)**
- **[Start automatically at logon](WeatherTray/docs/AUTOSTART.md)**
- **[Troubleshoot](WeatherTray/docs/TROUBLESHOOTING.md)**
- **[Developer and testing notes](WeatherTray/docs/DEVELOPMENT.md)**
- **[Version history](WeatherTray/CHANGELOG.md)**

## Repository organization

Each script or utility lives in its own named folder, with its own README, release history, and supporting documentation. Independent tools may have different runtime requirements. Start with the project's README before installing.

~~~text
scripts/
├── LICENSE
├── README.md
└── WeatherTray/
    ├── WeatherTray.ps1
    ├── LICENSE
    ├── README.md
    ├── CHANGELOG.md
    └── docs/
        ├── INSTALLATION.md
        ├── AUTOSTART.md
        ├── CONFIGURATION.md
        ├── TROUBLESHOOTING.md
        └── DEVELOPMENT.md
~~~

## Installation philosophy

These are **source releases**, not packaged installers. Read the instructions for each project, keep the files in a stable local folder, and review scripts before execution. Where a scheduled task or logon automation is recommended, setup instructions are included; such tasks are **not created merely by downloading this repository**.

## Development note

WeatherTray was developed with assistance from OpenAI's ChatGPT, including support for code development and documentation. Michael Bendorf is responsible for the project's content, release decisions, and ongoing maintenance.

## License and contributions

Code in this repository, including WeatherTray, is available under the **[Mozilla Public License 2.0 (MPL-2.0)](LICENSE)**.

**Copyright © 2026 Michael Bendorf.**

MPL 2.0 allows personal and commercial use and modifications. When modified MPL-covered source files are distributed, those covered files must remain available under MPL 2.0. The license does **not** compel publication of private, internal-only changes.

If you improve one of these tools—even only for your own use—please consider opening an issue or pull request so others can benefit. This is a voluntary invitation, not an additional license condition.

External data services, APIs, and trademarks have their **own terms**, separate from the MPL license for this code. For example, WeatherTray's default Open-Meteo public endpoint is intended for **non-commercial** use; consult the project's data-service notes before commercial deployment.

## Disclaimer

These are independent personal projects, not official products of Microsoft, Open-Meteo, NOAA, or the National Weather Service. They are provided **as-is**. A weather notification script is a convenience display and **not a guaranteed emergency warning system**. Always consult official sources for urgent safety decisions.
