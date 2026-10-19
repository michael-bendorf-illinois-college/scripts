# Copyright (c) 2026 Michael Bendorf
# SPDX-License-Identifier: MPL-2.0
#
# WeatherTray.ps1
# Version 1.6.0
#
# Windows PowerShell 5.1 notification-area weather display using a hybrid:
# Open-Meteo for local weather conditions/forecast and the National Weather
# Service API for official watches and warnings.
#
# Features:
#   - Uses Open-Meteo at the configured exact coordinates for local conditions.
#   - Displays the local model temperature in large, high-contrast tray digits.
#   - Prefixes the tray temperature with ! while a watch or warning is active.
#   - Adds a companion tray icon using an emoji for the local weather condition.
#   - Shows U.S. customary and metric units together.
#   - Shows feels-like temperature, humidity, wind/gusts, dew point, pressure,
#     visibility, forecast high/low, and update time.
#   - Checks official active NWS watches/warnings for the configured point.
#   - Includes a Settings dialog for location name and exact decimal coordinates.
#   - Shows a Windows notification/banner for NEW watches and warnings only.
#   - Remembers previously-notified alert IDs across restarts.
#   - No third-party modules or administrator rights required.

# ----------------------------
# Configuration
# ----------------------------
# Defaults are used only when no saved settings file exists.
$DefaultLocationName = 'Carlinville, IL'
$DefaultCoordinates  = '39.280,-89.880'
$RefreshMinutes      = 15

# NWS requests a descriptive User-Agent. Open-Meteo also receives it.
$UserAgent = 'WeatherTray-PowerShell/1.6.0'

# ----------------------------
# Initialization
# ----------------------------
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class WeatherTrayNative
{
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern bool DestroyIcon(IntPtr handle);
}
"@

# Prevent multiple copies from running in the same interactive user session.
$createdNew = $false
$mutex = [System.Threading.Mutex]::new(
    $true,
    'Local\WeatherTray-PowerShell-5.1',
    [ref]$createdNew
)

if (-not $createdNew) {
    exit 0
}

$DataDirectory = Join-Path $env:LOCALAPPDATA 'WeatherTray'
$LogPath       = Join-Path $DataDirectory 'WeatherTray.log'
$StatePath     = Join-Path $DataDirectory 'WeatherTrayState.json'
$SettingsPath  = Join-Path $DataDirectory 'WeatherTraySettings.json'

if (-not (Test-Path -LiteralPath $DataDirectory)) {
    New-Item -ItemType Directory -Path $DataDirectory -Force | Out-Null
}

function Write-WeatherLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    try {
        # Keep logging intentionally small. Roll over at roughly 1 MB.
        if ((Test-Path -LiteralPath $LogPath) -and
            ((Get-Item -LiteralPath $LogPath).Length -gt 1MB)) {

            $oldLog = "$LogPath.old"
            Remove-Item -LiteralPath $oldLog -Force -ErrorAction SilentlyContinue
            Move-Item -LiteralPath $LogPath -Destination $oldLog -Force
        }

        $timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
        Add-Content -LiteralPath $LogPath `
            -Value "$timestamp  $Message" `
            -Encoding UTF8
    }
    catch {
        # Logging should never terminate the tray application.
    }
}

function Limit-Text {
    param(
        [AllowNull()]
        [string]$Text,

        [int]$MaximumLength = 200
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    $clean = ($Text -replace '\s+', ' ').Trim()

    if ($clean.Length -le $MaximumLength) {
        return $clean
    }

    if ($MaximumLength -le 3) {
        return $clean.Substring(0, $MaximumLength)
    }

    return $clean.Substring(0, $MaximumLength - 3) + '...'
}


function Try-ParseCoordinates {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [ref]$LatitudeOut,

        [Parameter(Mandatory = $true)]
        [ref]$LongitudeOut,

        [Parameter(Mandatory = $true)]
        [ref]$NormalizedOut
    )

    $value = $Text.Trim()

    # Decimal latitude,longitude only. Deliberately reject DMS symbols and
    # hemisphere letters so a value such as 39°16'58.4"N is not misread.
    if ($value -notmatch '^[-+]?\d{1,2}(?:\.\d+)?\s*,\s*[-+]?\d{1,3}(?:\.\d+)?$') {
        return $false
    }

    $parts = $value -split ','
    if ($parts.Count -ne 2) {
        return $false
    }

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $style = [System.Globalization.NumberStyles]::Float

    $latitude = 0.0
    $longitude = 0.0

    if (-not [double]::TryParse($parts[0].Trim(), $style, $culture, [ref]$latitude)) {
        return $false
    }

    if (-not [double]::TryParse($parts[1].Trim(), $style, $culture, [ref]$longitude)) {
        return $false
    }

    if (($latitude -lt -90) -or ($latitude -gt 90) -or
        ($longitude -lt -180) -or ($longitude -gt 180)) {
        return $false
    }

    $normalized = [string]::Format(
        $culture,
        '{0:0.#####},{1:0.#####}',
        $latitude,
        $longitude
    )

    $LatitudeOut.Value = $latitude
    $LongitudeOut.Value = $longitude
    $NormalizedOut.Value = $normalized
    return $true
}

function Save-WeatherSettings {
    try {
        [pscustomobject]@{
            LocationName = $script:LocationName
            Coordinates  = $script:Coordinates
            SavedAt      = (Get-Date).ToString('o')
        } |
            ConvertTo-Json -Depth 3 |
            Set-Content -LiteralPath $SettingsPath -Encoding UTF8

        Write-WeatherLog (
            'Settings saved: {0} at {1}.' -f
            $script:LocationName,
            $script:Coordinates
        )
    }
    catch {
        Write-WeatherLog "Could not save settings: $($_.Exception.Message)"
        throw
    }
}

function Load-WeatherSettings {
    $locationName = $DefaultLocationName
    $coordinateText = $DefaultCoordinates

    if (Test-Path -LiteralPath $SettingsPath) {
        try {
            $saved = Get-Content -LiteralPath $SettingsPath -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop

            if (-not [string]::IsNullOrWhiteSpace([string]$saved.LocationName)) {
                $locationName = [string]$saved.LocationName
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$saved.Coordinates)) {
                $coordinateText = [string]$saved.Coordinates
            }
        }
        catch {
            Write-WeatherLog "Could not read settings; using defaults: $($_.Exception.Message)"
        }
    }

    $latitude = 0.0
    $longitude = 0.0
    $normalized = ''

    if (-not (Try-ParseCoordinates `
            -Text $coordinateText `
            -LatitudeOut ([ref]$latitude) `
            -LongitudeOut ([ref]$longitude) `
            -NormalizedOut ([ref]$normalized))) {

        $coordinateText = $DefaultCoordinates

        if (-not (Try-ParseCoordinates `
                -Text $coordinateText `
                -LatitudeOut ([ref]$latitude) `
                -LongitudeOut ([ref]$longitude) `
                -NormalizedOut ([ref]$normalized))) {

            throw 'The built-in default coordinates are invalid.'
        }
    }

    $script:LocationName = $locationName.Trim()
    $script:Latitude = $latitude
    $script:Longitude = $longitude
    $script:Coordinates = $normalized
}

Load-WeatherSettings

function Load-AlertState {
    $script:SeenAlertIds = @()

    if (-not (Test-Path -LiteralPath $StatePath)) {
        return
    }

    try {
        $state = Get-Content -LiteralPath $StatePath -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop

        if ($null -ne $state.SeenAlertIds) {
            $script:SeenAlertIds = @($state.SeenAlertIds | ForEach-Object {
                [string]$_
            })
        }
    }
    catch {
        Write-WeatherLog "Could not read alert state: $($_.Exception.Message)"
        $script:SeenAlertIds = @()
    }
}

function Save-AlertState {
    try {
        # IDs are unique and NWS alert IDs are not expected to be reused.
        # Keep only the newest 200 IDs so the state file remains tiny.
        $ids = @($script:SeenAlertIds | Select-Object -Unique)

        if ($ids.Count -gt 200) {
            $ids = @($ids | Select-Object -Last 200)
        }

        $script:SeenAlertIds = $ids

        [pscustomobject]@{
            SeenAlertIds = $ids
            SavedAt      = (Get-Date).ToString('o')
        } |
            ConvertTo-Json -Depth 3 |
            Set-Content -LiteralPath $StatePath -Encoding UTF8
    }
    catch {
        Write-WeatherLog "Could not save alert state: $($_.Exception.Message)"
    }
}

Load-AlertState

# ----------------------------
# Tray icon drawing
# ----------------------------
function New-TemperatureIcon {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    # Render larger than the final notification-area slot so Windows can
    # downscale the icon cleanly. The background is fully transparent.
    $canvasSize = 64
    $bitmap = New-Object System.Drawing.Bitmap $canvasSize, $canvasSize
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

    try {
        $graphics.SmoothingMode =
            [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

        $graphics.InterpolationMode =
            [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

        $graphics.PixelOffsetMode =
            [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

        # AntiAliasGridFit works better than ClearType on a transparent icon.
        $graphics.TextRenderingHint =
            [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

        $graphics.Clear([System.Drawing.Color]::Transparent)

        # GenericTypographic minimizes the extra padding DrawString normally
        # reserves around text, allowing the digits to occupy more of the icon.
        $format =
            [System.Drawing.StringFormat]::GenericTypographic.Clone()

        try {
            $format.Alignment =
                [System.Drawing.StringAlignment]::Center

            $format.LineAlignment =
                [System.Drawing.StringAlignment]::Center

            $format.FormatFlags =
                $format.FormatFlags -bor
                [System.Drawing.StringFormatFlags]::NoWrap -bor
                [System.Drawing.StringFormatFlags]::NoClip

            # Find the largest font that fits the available square. This keeps
            # 2-digit temperatures very large while automatically shrinking
            # for values such as 100 or alert forms such as !72 / !100.
            $maximumWidth  = 63
            $maximumHeight = 62
            $fontSize = 60
            $font = $null

            while ($fontSize -ge 18) {
                if ($null -ne $font) {
                    $font.Dispose()
                }

                $font = New-Object System.Drawing.Font(
                    'Segoe UI',
                    $fontSize,
                    [System.Drawing.FontStyle]::Bold,
                    [System.Drawing.GraphicsUnit]::Pixel
                )

                $measured = $graphics.MeasureString(
                    $Text,
                    $font,
                    1000,
                    $format
                )

                if (($measured.Width -le $maximumWidth) -and
                    ($measured.Height -le $maximumHeight)) {

                    break
                }

                $fontSize--
            }

            try {
                # A small upward adjustment visually centers Segoe UI numerals
                # inside the square at notification-area sizes.
                $rectangle =
                    [System.Drawing.RectangleF]::new(
                        0,
                        -1,
                        $canvasSize,
                        $canvasSize
                    )

                $graphics.DrawString(
                    $Text,
                    $font,
                    [System.Drawing.Brushes]::White,
                    $rectangle,
                    $format
                )
            }
            finally {
                if ($null -ne $font) {
                    $font.Dispose()
                }
            }
        }
        finally {
            $format.Dispose()
        }

        $hIcon = $bitmap.GetHicon()

        try {
            $temporaryIcon =
                [System.Drawing.Icon]::FromHandle($hIcon)

            $clonedIcon = $temporaryIcon.Clone()
            $temporaryIcon.Dispose()

            return $clonedIcon
        }
        finally {
            [WeatherTrayNative]::DestroyIcon($hIcon) | Out-Null
        }
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Set-TrayTemperature {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    # Store the base value separately from the alert cue so the icon can be
    # redrawn immediately when a watch/warning starts or clears.
    $script:LastTrayTemperatureText = $Text

    $displayText = $Text

    if (($script:ActiveAlerts.Count -gt 0) -and
        ($Text -match '^-?\d+$')) {

        $displayText = '!' + $Text
    }

    $newIcon = New-TemperatureIcon -Text $displayText
    $oldIcon = $script:NotifyIcon.Icon

    $script:NotifyIcon.Icon = $newIcon

    if ($null -ne $oldIcon) {
        $oldIcon.Dispose()
    }
}

function Refresh-TrayIcon {
    if (-not [string]::IsNullOrWhiteSpace(
            [string]$script:LastTrayTemperatureText
        )) {

        Set-TrayTemperature `
            -Text $script:LastTrayTemperatureText
    }
}


function Get-ConditionEmoji {
    param(
        [AllowNull()]
        [string]$Condition
    )

    if ([string]::IsNullOrWhiteSpace($Condition)) {
        return '🌡️'
    }

    # Order matters: more specific/hazardous conditions are checked first.
    switch -Regex ($Condition) {
        '(?i)thunder|t-?storm|lightning' {
            return '⛈️'
        }

        '(?i)freezing rain|ice pellets?|sleet|wintry mix|ice storm' {
            return '🌨️'
        }

        '(?i)snow|flurr|blizzard' {
            return '🌨️'
        }

        '(?i)rain|shower|drizzle' {
            return '🌧️'
        }

        '(?i)fog|mist|haze|smoke' {
            return '🌫️'
        }

        '(?i)mostly sunny|partly sunny|partly cloudy|mostly clear' {
            return '⛅'
        }

        '(?i)cloud|overcast' {
            return '☁️'
        }

        '(?i)windy|breezy|wind' {
            return '💨'
        }

        '(?i)sunny|clear|fair' {
            return '☀️'
        }

        default {
            return '🌡️'
        }
    }
}

function New-ConditionEmojiIcon {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Emoji
    )

    # Render at 64x64 and let Windows scale to the current notification-area
    # size. Segoe UI Emoji is used explicitly; actual color rendering depends
    # on the Windows/GDI+ emoji support available on the machine.
    $canvasSize = 64
    $bitmap = New-Object System.Drawing.Bitmap $canvasSize, $canvasSize
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

    try {
        $graphics.SmoothingMode =
            [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

        $graphics.InterpolationMode =
            [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

        $graphics.PixelOffsetMode =
            [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

        $graphics.TextRenderingHint =
            [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

        $graphics.Clear([System.Drawing.Color]::Transparent)

        $format =
            [System.Drawing.StringFormat]::GenericTypographic.Clone()

        try {
            $format.Alignment =
                [System.Drawing.StringAlignment]::Center

            $format.LineAlignment =
                [System.Drawing.StringAlignment]::Center

            $format.FormatFlags =
                $format.FormatFlags -bor
                [System.Drawing.StringFormatFlags]::NoWrap -bor
                [System.Drawing.StringFormatFlags]::NoClip

            $fontSize = 58
            $font = $null

            while ($fontSize -ge 20) {
                if ($null -ne $font) {
                    $font.Dispose()
                }

                $font = New-Object System.Drawing.Font(
                    'Segoe UI Emoji',
                    $fontSize,
                    [System.Drawing.FontStyle]::Regular,
                    [System.Drawing.GraphicsUnit]::Pixel
                )

                $measured = $graphics.MeasureString(
                    $Emoji,
                    $font,
                    1000,
                    $format
                )

                if (($measured.Width -le 63) -and
                    ($measured.Height -le 63)) {

                    break
                }

                $fontSize--
            }

            try {
                $rectangle =
                    [System.Drawing.RectangleF]::new(
                        0,
                        -1,
                        $canvasSize,
                        $canvasSize
                    )

                $graphics.DrawString(
                    $Emoji,
                    $font,
                    [System.Drawing.Brushes]::White,
                    $rectangle,
                    $format
                )
            }
            finally {
                if ($null -ne $font) {
                    $font.Dispose()
                }
            }
        }
        finally {
            $format.Dispose()
        }

        $hIcon = $bitmap.GetHicon()

        try {
            $temporaryIcon =
                [System.Drawing.Icon]::FromHandle($hIcon)

            $clonedIcon = $temporaryIcon.Clone()
            $temporaryIcon.Dispose()

            return $clonedIcon
        }
        finally {
            [WeatherTrayNative]::DestroyIcon($hIcon) | Out-Null
        }
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Set-ConditionIcon {
    param(
        [AllowNull()]
        [string]$Condition
    )

    $emoji = Get-ConditionEmoji -Condition $Condition
    $newIcon = New-ConditionEmojiIcon -Emoji $emoji
    $oldIcon = $script:ConditionNotifyIcon.Icon

    $script:ConditionNotifyIcon.Icon = $newIcon

    if ($null -ne $oldIcon) {
        $oldIcon.Dispose()
    }

    if ([string]::IsNullOrWhiteSpace($Condition)) {
        $conditionText = 'Weather condition unavailable'
    }
    else {
        $conditionText = $Condition
    }

    $tooltip = '{0} | {1}' -f $LocationName, $conditionText

    if ($tooltip.Length -gt 63) {
        $tooltip = $tooltip.Substring(0, 63)
    }

    $script:ConditionNotifyIcon.Text = $tooltip
}

function Set-TrayTooltip {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    # NotifyIcon.Text has a short maximum length on .NET Framework.
    if ($Text.Length -gt 63) {
        $Text = $Text.Substring(0, 63)
    }

    $script:NotifyIcon.Text = $Text
}

# ----------------------------
# HTTP / weather helpers
# ----------------------------
function Invoke-NwsRequest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    return Invoke-RestMethod `
        -Uri $Uri `
        -Method Get `
        -UserAgent $UserAgent `
        -Headers @{ Accept = 'application/geo+json' } `
        -TimeoutSec 20 `
        -ErrorAction Stop
}

function Invoke-OpenMeteoRequest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    return Invoke-RestMethod `
        -Uri $Uri `
        -Method Get `
        -UserAgent $UserAgent `
        -TimeoutSec 20 `
        -ErrorAction Stop
}

function Convert-CelsiusToFahrenheit {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }

    try {
        return [int][Math]::Round(
            ([double]$Value * 9 / 5) + 32
        )
    }
    catch {
        return $null
    }
}

function Convert-TemperatureToFahrenheit {
    param(
        $Value,
        [string]$UnitCode
    )

    if ($null -eq $Value) {
        return $null
    }

    try {
        $number = [double]$Value
    }
    catch {
        return $null
    }

    if ($UnitCode -match 'degC') {
        return Convert-CelsiusToFahrenheit -Value $number
    }

    return [int][Math]::Round($number)
}


function Convert-FahrenheitToCelsius {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }

    try {
        return [int][Math]::Round(
            (([double]$Value - 32) * 5 / 9)
        )
    }
    catch {
        return $null
    }
}

function Convert-WindSpeedToKph {
    param(
        $Value,
        [string]$UnitCode
    )

    if ($null -eq $Value) {
        return $null
    }

    try {
        $number = [double]$Value
    }
    catch {
        return $null
    }

    if ($UnitCode -match 'km_h-1') {
        return [int][Math]::Round($number)
    }

    if ($UnitCode -match 'm_s-1') {
        return [int][Math]::Round($number * 3.6)
    }

    # Fall back to treating an unknown speed unit as mph.
    return [int][Math]::Round($number * 1.609344)
}

function Convert-PressureToHpa {
    param(
        $Value,
        [string]$UnitCode
    )

    if ($null -eq $Value) {
        return $null
    }

    try {
        $number = [double]$Value
    }
    catch {
        return $null
    }

    if ($UnitCode -match '(?i)(^|:)Pa$') {
        return [Math]::Round($number / 100, 1)
    }

    if ($UnitCode -match '(?i)hPa') {
        return [Math]::Round($number, 1)
    }

    return $null
}

function Convert-HpaToInHg {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }

    try {
        return [Math]::Round(
            ([double]$Value * 0.0295299830714),
            2
        )
    }
    catch {
        return $null
    }
}

function Convert-VisibilityToKm {
    param(
        $Value,
        [string]$UnitCode
    )

    if ($null -eq $Value) {
        return $null
    }

    try {
        $number = [double]$Value
    }
    catch {
        return $null
    }

    if ($UnitCode -match '(?i)(^|:)m$') {
        return [Math]::Round($number / 1000, 1)
    }

    if ($UnitCode -match '(?i)km') {
        return [Math]::Round($number, 1)
    }

    return $null
}

function Convert-KmToMiles {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }

    try {
        return [Math]::Round(
            ([double]$Value * 0.621371),
            1
        )
    }
    catch {
        return $null
    }
}

function Format-TemperaturePair {
    param(
        $Fahrenheit
    )

    if ($null -eq $Fahrenheit) {
        return $null
    }

    $celsius = Convert-FahrenheitToCelsius -Value $Fahrenheit

    return '{0}°F / {1}°C' -f
        [int]$Fahrenheit,
        $celsius
}

function Convert-WindSpeedToMph {
    param(
        $Value,
        [string]$UnitCode
    )

    if ($null -eq $Value) {
        return $null
    }

    try {
        $number = [double]$Value
    }
    catch {
        return $null
    }

    if ($UnitCode -match 'km_h-1') {
        return [int][Math]::Round($number * 0.621371)
    }

    if ($UnitCode -match 'm_s-1') {
        return [int][Math]::Round($number * 2.23694)
    }

    return [int][Math]::Round($number)
}

function Convert-DegreesToCompass {
    param($Degrees)

    if ($null -eq $Degrees) {
        return $null
    }

    try {
        $value = [double]$Degrees
    }
    catch {
        return $null
    }

    $directions = @(
        'N', 'NNE', 'NE', 'ENE',
        'E', 'ESE', 'SE', 'SSE',
        'S', 'SSW', 'SW', 'WSW',
        'W', 'WNW', 'NW', 'NNW'
    )

    $index = [int][Math]::Floor((($value + 11.25) % 360) / 22.5)
    return $directions[$index]
}

function Get-WholeNumber {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }

    try {
        return [int][Math]::Round([double]$Value)
    }
    catch {
        return $null
    }
}

function Get-WeatherDescription {
    param($WeatherCode)

    if ($null -eq $WeatherCode) {
        return 'Current conditions'
    }

    switch ([int]$WeatherCode) {
        0  { return 'Clear sky' }
        1  { return 'Mainly clear' }
        2  { return 'Partly cloudy' }
        3  { return 'Overcast' }
        45 { return 'Fog' }
        48 { return 'Depositing rime fog' }
        51 { return 'Light drizzle' }
        53 { return 'Moderate drizzle' }
        55 { return 'Dense drizzle' }
        56 { return 'Light freezing drizzle' }
        57 { return 'Dense freezing drizzle' }
        61 { return 'Slight rain' }
        63 { return 'Moderate rain' }
        65 { return 'Heavy rain' }
        66 { return 'Light freezing rain' }
        67 { return 'Heavy freezing rain' }
        71 { return 'Slight snow' }
        73 { return 'Moderate snow' }
        75 { return 'Heavy snow' }
        77 { return 'Snow grains' }
        80 { return 'Slight rain showers' }
        81 { return 'Moderate rain showers' }
        82 { return 'Violent rain showers' }
        85 { return 'Slight snow showers' }
        86 { return 'Heavy snow showers' }
        95 { return 'Thunderstorm' }
        96 { return 'Thunderstorm with slight hail' }
        99 { return 'Thunderstorm with heavy hail' }
        default { return 'Current conditions' }
    }
}

function Get-DewPointFahrenheit {
    param(
        $TemperatureFahrenheit,
        $RelativeHumidity
    )

    if (($null -eq $TemperatureFahrenheit) -or
        ($null -eq $RelativeHumidity)) {
        return $null
    }

    try {
        $temperatureC = ([double]$TemperatureFahrenheit - 32) * 5 / 9
        $rh = [double]$RelativeHumidity

        if ($rh -le 0) {
            return $null
        }

        # Magnus approximation over the ordinary surface-weather range.
        $a = 17.625
        $b = 243.04
        $gamma = [Math]::Log($rh / 100.0) +
            (($a * $temperatureC) / ($b + $temperatureC))

        $dewPointC = ($b * $gamma) / ($a - $gamma)
        return [int][Math]::Round(($dewPointC * 9 / 5) + 32)
    }
    catch {
        return $null
    }
}

function Update-ApiUris {
    $culture = [System.Globalization.CultureInfo]::InvariantCulture

    $latitudeText = $script:Latitude.ToString('0.#####', $culture)
    $longitudeText = $script:Longitude.ToString('0.#####', $culture)
    $coordinate = "$latitudeText,$longitudeText"

    $currentVariables = @(
        'temperature_2m',
        'relative_humidity_2m',
        'apparent_temperature',
        'weather_code',
        'pressure_msl',
        'visibility',
        'wind_speed_10m',
        'wind_direction_10m',
        'wind_gusts_10m'
    ) -join ','

    $dailyVariables = @(
        'temperature_2m_max',
        'temperature_2m_min'
    ) -join ','

    $script:OpenMeteoUri =
        'https://api.open-meteo.com/v1/forecast' +
        "?latitude=$latitudeText" +
        "&longitude=$longitudeText" +
        "&current=$currentVariables" +
        "&daily=$dailyVariables" +
        '&temperature_unit=fahrenheit' +
        '&wind_speed_unit=mph' +
        '&timezone=auto' +
        '&forecast_days=2'

    $script:AlertsUri =
        "https://api.weather.gov/alerts/active?point=$coordinate"

    $script:ForecastWebUri =
        "https://forecast.weather.gov/MapClick.php?lat=$latitudeText&lon=$longitudeText"
}

Update-ApiUris

$script:LastWeather          = $null
$script:ActiveAlerts         = @()
$script:LastTrayTemperatureText = $null
$script:RefreshInProgress    = $false

# ----------------------------
# Weather display
# ----------------------------
function Show-WeatherBalloon {
    if ($null -eq $script:LastWeather) {
        $script:NotifyIcon.BalloonTipTitle = $LocationName
        $script:NotifyIcon.BalloonTipText =
            'Weather data is not available yet.'

        $script:NotifyIcon.BalloonTipIcon =
            [System.Windows.Forms.ToolTipIcon]::Info

        $script:NotifyIcon.ShowBalloonTip(7000)
        return
    }

    $w = $script:LastWeather
    $details = New-Object System.Collections.Generic.List[string]

    $conditionLine = Format-TemperaturePair -Fahrenheit $w.Temperature

    if (-not [string]::IsNullOrWhiteSpace($w.Condition)) {
        $conditionLine += ' — ' + $w.Condition
    }

    $details.Add($conditionLine)

    if (($null -ne $w.FeelsLike) -and
        ($w.FeelsLike -ne $w.Temperature)) {

        $details.Add(
            ('Feels like {0}' -f
                (Format-TemperaturePair -Fahrenheit $w.FeelsLike))
        )
    }

    if (-not [string]::IsNullOrWhiteSpace($w.Wind)) {
        $details.Add(
            ('Wind {0}' -f $w.Wind)
        )
    }

    if (-not [string]::IsNullOrWhiteSpace($w.WindGust)) {
        $details.Add(
            ('Gust {0}' -f $w.WindGust)
        )
    }

    if ($null -ne $w.Humidity) {
        $details.Add(
            ('Humidity {0}%' -f $w.Humidity)
        )
    }

    if ($null -ne $w.DewPoint) {
        $details.Add(
            ('Dew point {0}' -f
                (Format-TemperaturePair -Fahrenheit $w.DewPoint))
        )
    }

    if (($null -ne $w.PressureInHg) -and
        ($null -ne $w.PressureHpa)) {

        $details.Add(
            ('Pressure {0:N2} inHg / {1:N1} hPa' -f
                $w.PressureInHg,
                $w.PressureHpa)
        )
    }

    if (($null -ne $w.VisibilityMiles) -and
        ($null -ne $w.VisibilityKm)) {

        $details.Add(
            ('Visibility {0:N1} mi / {1:N1} km' -f
                $w.VisibilityMiles,
                $w.VisibilityKm)
        )
    }

    if (-not [string]::IsNullOrWhiteSpace($w.HighText)) {
        $details.Add($w.HighText)
    }

    if (-not [string]::IsNullOrWhiteSpace($w.LowText)) {
        $details.Add($w.LowText)
    }

    if ($script:ActiveAlerts.Count -gt 0) {
        $details.Add(
            ('{0} active watch/warning alert(s)' -f
                $script:ActiveAlerts.Count)
        )
    }

    if ($null -ne $w.ObservedAt) {
        $details.Add(
            ('Open-Meteo {0}' -f
                $w.ObservedAt.ToString('h:mm tt'))
        )
    }

    $script:NotifyIcon.BalloonTipTitle = $LocationName
    $script:NotifyIcon.BalloonTipText =
        Limit-Text -Text ($details -join [Environment]::NewLine) `
            -MaximumLength 300

    $script:NotifyIcon.BalloonTipIcon =
        [System.Windows.Forms.ToolTipIcon]::Info

    $script:NotifyIcon.ShowBalloonTip(10000)
}

function Update-Weather {
    if ($script:RefreshInProgress) {
        return
    }

    $script:RefreshInProgress = $true

    try {
        $weather = Invoke-OpenMeteoRequest -Uri $script:OpenMeteoUri
        $p = $weather.current

        if ($null -eq $p.temperature_2m) {
            throw 'Open-Meteo did not return a usable current temperature.'
        }

        $temperature = [int][Math]::Round([double]$p.temperature_2m)
        $temperatureC = Convert-FahrenheitToCelsius -Value $temperature

        $feelsLike = $null
        if ($null -ne $p.apparent_temperature) {
            $feelsLike = [int][Math]::Round([double]$p.apparent_temperature)
        }
        if ($null -eq $feelsLike) {
            $feelsLike = $temperature
        }
        $feelsLikeC = Convert-FahrenheitToCelsius -Value $feelsLike

        $humidity = Get-WholeNumber -Value $p.relative_humidity_2m
        $dewPoint = Get-DewPointFahrenheit `
            -TemperatureFahrenheit $temperature `
            -RelativeHumidity $humidity

        $windSpeedMph = $null
        $windSpeedKph = $null
        if ($null -ne $p.wind_speed_10m) {
            $windSpeedMph = [int][Math]::Round([double]$p.wind_speed_10m)
            $windSpeedKph = [int][Math]::Round($windSpeedMph * 1.609344)
        }

        $windGustMph = $null
        $windGustKph = $null
        if ($null -ne $p.wind_gusts_10m) {
            $windGustMph = [int][Math]::Round([double]$p.wind_gusts_10m)
            $windGustKph = [int][Math]::Round($windGustMph * 1.609344)
        }

        $windDirection = Convert-DegreesToCompass -Degrees $p.wind_direction_10m

        $wind = $null
        if (($null -ne $windSpeedMph) -and ($null -ne $windSpeedKph)) {
            if ($windSpeedMph -le 1) {
                $wind = 'Calm'
            }
            elseif (-not [string]::IsNullOrWhiteSpace($windDirection)) {
                $wind = '{0} {1} mph / {2} km/h' -f
                    $windDirection,
                    $windSpeedMph,
                    $windSpeedKph
            }
            else {
                $wind = '{0} mph / {1} km/h' -f
                    $windSpeedMph,
                    $windSpeedKph
            }
        }

        $windGust = $null
        if (($null -ne $windGustMph) -and
            ($null -ne $windGustKph) -and
            ($windGustMph -gt 0)) {

            $windGust = '{0} mph / {1} km/h' -f
                $windGustMph,
                $windGustKph
        }

        $pressureHpa = $null
        if ($null -ne $p.pressure_msl) {
            $pressureHpa = [Math]::Round([double]$p.pressure_msl, 1)
        }
        $pressureInHg = Convert-HpaToInHg -Value $pressureHpa

        $visibilityKm = $null
        if ($null -ne $p.visibility) {
            $visibilityKm = [Math]::Round(([double]$p.visibility / 1000), 1)
        }
        $visibilityMiles = Convert-KmToMiles -Value $visibilityKm

        $condition = Get-WeatherDescription -WeatherCode $p.weather_code

        $modelTime = $null
        if (-not [string]::IsNullOrWhiteSpace([string]$p.time)) {
            try {
                $modelTime = [datetime]::Parse([string]$p.time)
            }
            catch {
                $modelTime = $null
            }
        }

        $highText = $null
        $lowText = $null

        if (($null -ne $weather.daily) -and
            (@($weather.daily.temperature_2m_max).Count -gt 0)) {

            $high = [int][Math]::Round(
                [double]@($weather.daily.temperature_2m_max)[0]
            )
            $highText = 'Today: High {0}' -f
                (Format-TemperaturePair -Fahrenheit $high)
        }

        if (($null -ne $weather.daily) -and
            (@($weather.daily.temperature_2m_min).Count -gt 0)) {

            $low = [int][Math]::Round(
                [double]@($weather.daily.temperature_2m_min)[0]
            )
            $lowText = 'Today: Low {0}' -f
                (Format-TemperaturePair -Fahrenheit $low)
        }

        $updated = Get-Date

        $script:LastWeather = [pscustomobject]@{
            Temperature     = $temperature
            TemperatureC    = $temperatureC
            FeelsLike       = $feelsLike
            FeelsLikeC      = $feelsLikeC
            Condition       = $condition
            Humidity        = $humidity
            DewPoint        = $dewPoint
            Wind            = $wind
            WindGust        = $windGust
            WindDirection   = $windDirection
            WindSpeedMph    = $windSpeedMph
            WindSpeedKph    = $windSpeedKph
            WindGustMph     = $windGustMph
            WindGustKph     = $windGustKph
            PressureInHg    = $pressureInHg
            PressureHpa     = $pressureHpa
            VisibilityMiles = $visibilityMiles
            VisibilityKm    = $visibilityKm
            HighText        = $highText
            LowText         = $lowText
            ObservedAt      = $modelTime
            Updated         = $updated
            Source          = 'Open-Meteo local model'
        }

        Set-TrayTemperature -Text ([string]$temperature)
        Set-ConditionIcon -Condition $condition

        $tooltipParts = New-Object System.Collections.Generic.List[string]
        $tooltipParts.Add(
            ('{0}°F/{1}°C' -f $temperature, $temperatureC)
        )

        if (($null -ne $windSpeedMph) -and ($null -ne $windSpeedKph)) {
            if ($windSpeedMph -le 1) {
                $tooltipParts.Add('Calm')
            }
            elseif (-not [string]::IsNullOrWhiteSpace($windDirection)) {
                $tooltipParts.Add(
                    ('{0} {1} mph/{2} km/h' -f
                        $windDirection,
                        $windSpeedMph,
                        $windSpeedKph)
                )
            }
            else {
                $tooltipParts.Add(
                    ('{0} mph/{1} km/h' -f
                        $windSpeedMph,
                        $windSpeedKph)
                )
            }
        }

        if ($null -ne $humidity) {
            $tooltipParts.Add(('RH {0}%' -f $humidity))
        }

        Set-TrayTooltip -Text ($tooltipParts -join ' | ')

        $script:StatusMenuItem.Text =
            '{0}°F / {1}°C — {2}' -f
            $temperature,
            $temperatureC,
            (Limit-Text -Text $condition -MaximumLength 34)

        $script:StationMenuItem.Text =
            'Source: Open-Meteo @ {0}' -f $script:Coordinates

        if ($null -ne $modelTime) {
            $script:UpdatedMenuItem.Text =
                'Open-Meteo {0}' -f $modelTime.ToString('h:mm tt')
        }
        else {
            $script:UpdatedMenuItem.Text =
                'Refreshed {0}' -f $updated.ToString('h:mm tt')
        }

        Write-WeatherLog (
            'Weather refreshed from Open-Meteo: {0}°F/{1}°C, {2}; coordinates {3}.' -f
            $temperature,
            $temperatureC,
            $condition,
            $script:Coordinates
        )
    }
    catch {
        $message = $_.Exception.Message
        Write-WeatherLog "Weather refresh failed: $message"

        if ($null -eq $script:LastWeather) {
            Set-TrayTemperature -Text '!'
            Set-ConditionIcon -Condition $null
            Set-TrayTooltip -Text "$LocationName | Weather unavailable"

            $script:StatusMenuItem.Text = 'Weather unavailable'
            $script:UpdatedMenuItem.Text = 'Refresh failed'
        }
        else {
            $last = $script:LastWeather

            Set-TrayTooltip -Text (
                '{0} | {1}°F | stale data' -f
                $LocationName,
                $last.Temperature
            )

            $script:UpdatedMenuItem.Text =
                'Refresh failed — last good {0}' -f
                $last.Updated.ToString('h:mm tt')
        }
    }
    finally {
        $script:RefreshInProgress = $false
    }
}

# ----------------------------
# NWS watch/warning alerts
# ----------------------------
function Get-AlertId {
    param($AlertFeature)

    $id = [string]$AlertFeature.id

    if ([string]::IsNullOrWhiteSpace($id)) {
        $id = [string]$AlertFeature.properties.id
    }

    if ([string]::IsNullOrWhiteSpace($id)) {
        # Extremely defensive fallback if an upstream response lacks an ID.
        $id = '{0}|{1}|{2}' -f
            [string]$AlertFeature.properties.event,
            [string]$AlertFeature.properties.onset,
            [string]$AlertFeature.properties.expires
    }

    return $id
}

function Show-AlertNotification {
    param(
        [Parameter(Mandatory = $true)]
        [array]$NewAlerts
    )

    if ($NewAlerts.Count -eq 0) {
        return
    }

    if ($NewAlerts.Count -eq 1) {
        $alert = $NewAlerts[0]
        $event = [string]$alert.properties.event
        $headline = [string]$alert.properties.headline

        if ([string]::IsNullOrWhiteSpace($headline)) {
            $headline = [string]$alert.properties.description
        }

        $bodyParts =
            New-Object System.Collections.Generic.List[string]

        $expires = [string]$alert.properties.ends

        if ([string]::IsNullOrWhiteSpace($expires)) {
            $expires = [string]$alert.properties.expires
        }

        if (-not [string]::IsNullOrWhiteSpace($expires)) {
            try {
                $endTime =
                    [DateTimeOffset]::Parse($expires).LocalDateTime

                $bodyParts.Add(
                    ('Until {0}' -f
                        $endTime.ToString('ddd h:mm tt'))
                )
            }
            catch {
                # Ignore malformed/missing expiration time.
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($headline)) {
            $bodyParts.Add(
                (Limit-Text -Text $headline -MaximumLength 220)
            )
        }

        if ($bodyParts.Count -eq 0) {
            $bodyParts.Add(
                'An active NWS watch or warning applies to the configured location.'
            )
        }

        $script:NotifyIcon.BalloonTipTitle =
            "NWS $event"

        $script:NotifyIcon.BalloonTipText =
            Limit-Text `
                -Text ($bodyParts -join [Environment]::NewLine) `
                -MaximumLength 300
    }
    else {
        $events = @(
            $NewAlerts |
                ForEach-Object {
                    [string]$_.properties.event
                } |
                Where-Object {
                    -not [string]::IsNullOrWhiteSpace($_)
                } |
                Select-Object -Unique
        )

        $script:NotifyIcon.BalloonTipTitle =
            '{0} new NWS weather alerts' -f $NewAlerts.Count

        $script:NotifyIcon.BalloonTipText =
            Limit-Text `
                -Text ($events -join [Environment]::NewLine) `
                -MaximumLength 300
    }

    $script:NotifyIcon.BalloonTipIcon =
        [System.Windows.Forms.ToolTipIcon]::Warning

    # On modern Windows this notification-area balloon is surfaced by the
    # shell as a notification/banner. Display duration is ultimately governed
    # by Windows accessibility/notification settings.
    $script:NotifyIcon.ShowBalloonTip(15000)
}

function Update-Alerts {
    try {
        $response = Invoke-NwsRequest -Uri $script:AlertsUri

        $active = @(
            $response.features |
                Where-Object {
                    [string]$_.properties.event -match
                        '(?i)\b(?:warning|watch)\b'
                }
        )

        $script:ActiveAlerts = $active

        # Redraw immediately so the ! cue appears as soon as a watch/warning
        # becomes active and disappears as soon as the alert clears.
        Refresh-TrayIcon

        if ($active.Count -eq 0) {
            $script:AlertsMenuItem.Text =
                'No active watches/warnings'
        }
        elseif ($active.Count -eq 1) {
            $script:AlertsMenuItem.Text =
                '1 active: {0}' -f
                (Limit-Text `
                    -Text ([string]$active[0].properties.event) `
                    -MaximumLength 35)
        }
        else {
            $script:AlertsMenuItem.Text =
                '{0} active watches/warnings' -f
                $active.Count
        }

        $newAlerts = @()

        foreach ($alert in $active) {
            $id = Get-AlertId -AlertFeature $alert

            if ($script:SeenAlertIds -notcontains $id) {
                $newAlerts += $alert
                $script:SeenAlertIds += $id

                Write-WeatherLog (
                    'New alert: {0} ({1})' -f
                    [string]$alert.properties.event,
                    $id
                )
            }
        }

        if ($newAlerts.Count -gt 0) {
            Save-AlertState
            Show-AlertNotification -NewAlerts $newAlerts
        }
    }
    catch {
        Write-WeatherLog (
            'Alert refresh failed: {0}' -f
            $_.Exception.Message
        )

        $script:AlertsMenuItem.Text =
            'Alert check failed'
    }
}

function Refresh-All {
    Update-Weather
    Update-Alerts
}


function Show-SettingsDialog {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Weather Tray Settings'
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ShowInTaskbar = $false
    $form.ClientSize = [System.Drawing.Size]::new(500, 275)
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $locationLabel = New-Object System.Windows.Forms.Label
    $locationLabel.Text = 'Location name:'
    $locationLabel.Location = [System.Drawing.Point]::new(18, 18)
    $locationLabel.AutoSize = $true
    $form.Controls.Add($locationLabel)

    $locationBox = New-Object System.Windows.Forms.TextBox
    $locationBox.Location = [System.Drawing.Point]::new(18, 40)
    $locationBox.Size = [System.Drawing.Size]::new(460, 24)
    $locationBox.Text = $script:LocationName
    $form.Controls.Add($locationBox)

    $coordinatesLabel = New-Object System.Windows.Forms.Label
    $coordinatesLabel.Text = 'Exact coordinates:'
    $coordinatesLabel.Location = [System.Drawing.Point]::new(18, 78)
    $coordinatesLabel.AutoSize = $true
    $form.Controls.Add($coordinatesLabel)

    $coordinatesBox = New-Object System.Windows.Forms.TextBox
    $coordinatesBox.Location = [System.Drawing.Point]::new(18, 100)
    $coordinatesBox.Size = [System.Drawing.Size]::new(460, 24)
    $coordinatesBox.Text = $script:Coordinates
    $form.Controls.Add($coordinatesBox)

    $helpLabel = New-Object System.Windows.Forms.Label
    $helpLabel.Location = [System.Drawing.Point]::new(18, 134)
    $helpLabel.Size = [System.Drawing.Size]::new(460, 82)
    $helpLabel.Text = @"
Use decimal latitude,longitude, for example: 39.280,-89.880
Required style: xx.xxx,-xx.xxx (west longitudes are negative).
Do not enter degrees/minutes/seconds, for example:
39°16'58.4"N 89°53'28.2"W
"@
    $form.Controls.Add($helpLabel)

    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Text = 'Save'
    $saveButton.Size = [System.Drawing.Size]::new(90, 30)
    $saveButton.Location = [System.Drawing.Point]::new(288, 229)
    $form.Controls.Add($saveButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = 'Cancel'
    $cancelButton.Size = [System.Drawing.Size]::new(90, 30)
    $cancelButton.Location = [System.Drawing.Point]::new(388, 229)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)

    $form.AcceptButton = $saveButton
    $form.CancelButton = $cancelButton

    $saveButton.Add_Click({
        $latitude = 0.0
        $longitude = 0.0
        $normalized = ''

        if (-not (Try-ParseCoordinates `
                -Text $coordinatesBox.Text `
                -LatitudeOut ([ref]$latitude) `
                -LongitudeOut ([ref]$longitude) `
                -NormalizedOut ([ref]$normalized))) {

            [System.Windows.Forms.MessageBox]::Show(
                $form,
                "Coordinates must be decimal latitude,longitude.`r`n`r`nExample: 39.280,-89.880`r`n`r`nDo not use degrees/minutes/seconds such as 39°16'58.4`"N 89°53'28.2`"W.",
                'Invalid coordinates',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null

            return
        }

        $newLocationName = $locationBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($newLocationName)) {
            $newLocationName = 'Weather location'
        }

        $script:LocationName = $newLocationName
        $script:Latitude = $latitude
        $script:Longitude = $longitude
        $script:Coordinates = $normalized

        try {
            Save-WeatherSettings
            Update-ApiUris

            # Clear the currently-displayed alert state before querying NWS for
            # the newly configured point.
            $script:ActiveAlerts = @()
            Refresh-TrayIcon

            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $form.Close()
            Refresh-All
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                $form,
                "The settings could not be saved.`r`n`r`n$($_.Exception.Message)",
                'Weather Tray Settings',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    })

    [void]$form.ShowDialog()
    $form.Dispose()
}

# ----------------------------
# Notification-area UI
# ----------------------------
$script:NotifyIcon =
    New-Object System.Windows.Forms.NotifyIcon

$script:NotifyIcon.Visible = $true

$script:ConditionNotifyIcon =
    New-Object System.Windows.Forms.NotifyIcon

$script:ConditionNotifyIcon.Visible = $true

$contextMenu =
    New-Object System.Windows.Forms.ContextMenuStrip

$script:StatusMenuItem =
    New-Object System.Windows.Forms.ToolStripMenuItem

$script:StatusMenuItem.Text = 'Loading weather...'
$script:StatusMenuItem.Enabled = $false
[void]$contextMenu.Items.Add($script:StatusMenuItem)

$script:StationMenuItem =
    New-Object System.Windows.Forms.ToolStripMenuItem

$script:StationMenuItem.Text = 'Source: Open-Meteo local model'
$script:StationMenuItem.Enabled = $false
[void]$contextMenu.Items.Add($script:StationMenuItem)

$script:UpdatedMenuItem =
    New-Object System.Windows.Forms.ToolStripMenuItem

$script:UpdatedMenuItem.Text = 'Starting...'
$script:UpdatedMenuItem.Enabled = $false
[void]$contextMenu.Items.Add($script:UpdatedMenuItem)

$script:AlertsMenuItem =
    New-Object System.Windows.Forms.ToolStripMenuItem

$script:AlertsMenuItem.Text = 'Checking watches/warnings...'
$script:AlertsMenuItem.Enabled = $false
[void]$contextMenu.Items.Add($script:AlertsMenuItem)

[void]$contextMenu.Items.Add(
    (New-Object System.Windows.Forms.ToolStripSeparator)
)

$settingsItem =
    New-Object System.Windows.Forms.ToolStripMenuItem

$settingsItem.Text = 'Settings...'
$settingsItem.Add_Click({
    Show-SettingsDialog
})
[void]$contextMenu.Items.Add($settingsItem)

$refreshItem =
    New-Object System.Windows.Forms.ToolStripMenuItem

$refreshItem.Text = 'Refresh now'
$refreshItem.Add_Click({
    Refresh-All
})
[void]$contextMenu.Items.Add($refreshItem)

$forecastItem =
    New-Object System.Windows.Forms.ToolStripMenuItem

$forecastItem.Text = 'Open NWS forecast / alerts'
$forecastItem.Add_Click({
    try {
        Start-Process $script:ForecastWebUri
    }
    catch {
        Write-WeatherLog (
            'Could not open forecast page: {0}' -f
            $_.Exception.Message
        )
    }
})
[void]$contextMenu.Items.Add($forecastItem)

[void]$contextMenu.Items.Add(
    (New-Object System.Windows.Forms.ToolStripSeparator)
)

$exitItem =
    New-Object System.Windows.Forms.ToolStripMenuItem

$exitItem.Text = 'Exit'
$exitItem.Add_Click({
    $script:NotifyIcon.Visible = $false
    $script:ConditionNotifyIcon.Visible = $false
    [System.Windows.Forms.Application]::Exit()
})
[void]$contextMenu.Items.Add($exitItem)

$script:NotifyIcon.ContextMenuStrip = $contextMenu
$script:ConditionNotifyIcon.ContextMenuStrip = $contextMenu

$script:NotifyIcon.Add_MouseClick({
    param($sender, $eventArgs)

    if ($eventArgs.Button -eq
        [System.Windows.Forms.MouseButtons]::Left) {

        Show-WeatherBalloon
    }
})

$script:ConditionNotifyIcon.Add_MouseClick({
    param($sender, $eventArgs)

    if ($eventArgs.Button -eq
        [System.Windows.Forms.MouseButtons]::Left) {

        Show-WeatherBalloon
    }
})

# Clicking an alert/weather banner opens the NWS point forecast, which also
# exposes active hazards for the location.
$script:NotifyIcon.Add_BalloonTipClicked({
    try {
        Start-Process $script:ForecastWebUri
    }
    catch {
        Write-WeatherLog (
            'Could not open NWS page from notification: {0}' -f
            $_.Exception.Message
        )
    }
})

Set-TrayTemperature -Text '--'
Set-ConditionIcon -Condition $null
Set-TrayTooltip -Text "$LocationName | Loading weather..."
$script:ConditionNotifyIcon.Text = "$LocationName | Loading weather..."

$script:Timer =
    New-Object System.Windows.Forms.Timer

$script:Timer.Interval =
    [int]($RefreshMinutes * 60 * 1000)

$script:Timer.Add_Tick({
    Refresh-All
})

Write-WeatherLog 'WeatherTray v1.6.0 started.'

try {
    Refresh-All
    $script:Timer.Start()
    [System.Windows.Forms.Application]::Run()
}
finally {
    try {
        $script:Timer.Stop()
        $script:Timer.Dispose()
    }
    catch {}

    try {
        $script:NotifyIcon.Visible = $false

        if ($null -ne $script:NotifyIcon.Icon) {
            $script:NotifyIcon.Icon.Dispose()
        }

        $script:NotifyIcon.Dispose()
    }
    catch {}

    try {
        $script:ConditionNotifyIcon.Visible = $false

        if ($null -ne $script:ConditionNotifyIcon.Icon) {
            $script:ConditionNotifyIcon.Icon.Dispose()
        }

        $script:ConditionNotifyIcon.Dispose()
    }
    catch {}

    try {
        $contextMenu.Dispose()
    }
    catch {}

    try {
        $mutex.ReleaseMutex()
    }
    catch {}

    try {
        $mutex.Dispose()
    }
    catch {}

    Write-WeatherLog 'WeatherTray v1.6.0 stopped.'
}
