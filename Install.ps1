# PC Installer for Windows 11
# Put this file in the root of the USB stick.
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir = Join-Path $Root "Logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Log = Join-Path $LogDir ("install_{0}.log" -f (Get-Date -Format "yyyy-MM-dd_HH-mm-ss"))

function Log($msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg
    $line | Tee-Object -FilePath $Log -Append
}

function Find-Exe($dir) {
    if (!(Test-Path $dir)) { return $null }
    return Get-ChildItem -Path $dir -Filter *.exe -File -Recurse |
        Where-Object { $_.Name -notmatch 'uninstall|setupstub' } |
        Select-Object -First 1
}

Log "=== PC Installer started ==="
Log "USB root: $Root"

# 1. Start SDIO
$sdio = Find-Exe (Join-Path $Root "SDIO")
if ($sdio) {
    Log "Starting SDIO: $($sdio.FullName)"
    Start-Process -FilePath $sdio.FullName -WorkingDirectory $sdio.DirectoryName
} else {
    Log "WARNING: SDIO EXE not found in USB\SDIO"
}

# 2. Detect GPU
$gpus = Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name
Log "GPU detected: $($gpus -join ' | ')"

$gpuVendor = "UNKNOWN"
if ($gpus -match "NVIDIA") { $gpuVendor = "NVIDIA" }
elseif ($gpus -match "AMD|Radeon") { $gpuVendor = "AMD" }

Log "GPU vendor: $gpuVendor"

# 3. Start Yandex download in background.
# Recommended: place the FULL/offline Yandex installer in USB\Yandex
# If you want a network download, set YANDEX_URL below to the current
# official full-installer URL you use at work.
$yandexDir = Join-Path $Root "Yandex"
$yandexLocal = Get-ChildItem $yandexDir -Filter *.exe -File -ErrorAction SilentlyContinue | Select-Object -First 1

$downloadJob = $null
$YANDEX_URL = ""   # Example: "https://...." — put your approved official URL here.

if ($yandexLocal) {
    Log "Yandex installer already on USB: $($yandexLocal.Name)"
} elseif ($YANDEX_URL) {
    $dest = Join-Path $env:TEMP "YandexBrowser_Full.exe"
    Log "Starting Yandex download in background: $YANDEX_URL"
    try {
        $downloadJob = Start-BitsTransfer -Source $YANDEX_URL -Destination $dest `
            -Asynchronous -DisplayName "Yandex Browser download"
        Log "BITS job started."
    } catch {
        Log "ERROR starting Yandex download: $($_.Exception.Message)"
    }
} else {
    Log "Yandex download skipped: no local installer and YANDEX_URL is empty."
}

# 4. Start GPU installer
$gpuExe = $null
if ($gpuVendor -eq "NVIDIA") {
    $gpuExe = Find-Exe (Join-Path $Root "GPU\NVIDIA")
}
elseif ($gpuVendor -eq "AMD") {
    $gpuExe = Find-Exe (Join-Path $Root "GPU\AMD")
}

if ($gpuExe) {
    Log "Starting $gpuVendor GPU installer: $($gpuExe.FullName)"
    try {
        $p = Start-Process -FilePath $gpuExe.FullName -WorkingDirectory $gpuExe.DirectoryName -Wait -PassThru
        Log "GPU installer finished. ExitCode=$($p.ExitCode)"
    } catch {
        Log "ERROR running GPU installer: $($_.Exception.Message)"
    }
} else {
    Log "WARNING: No GPU installer found for $gpuVendor."
}

# 5. Wait for Yandex download, if any
if ($downloadJob) {
    Log "Waiting for Yandex download to finish..."
    try {
        while ($downloadJob.JobState -eq "Transferring") {
            Start-Sleep -Seconds 2
            $downloadJob = Get-BitsTransfer -JobId $downloadJob.JobId
        }
        if ($downloadJob.JobState -eq "Transferred") {
            Complete-BitsTransfer -BitsJob $downloadJob
            $yandexLocal = Get-Item (Join-Path $env:TEMP "YandexBrowser_Full.exe")
            Log "Yandex download completed: $($yandexLocal.FullName)"
        } else {
            Log "Yandex BITS job ended with state: $($downloadJob.JobState)"
        }
    } catch {
        Log "ERROR completing Yandex download: $($_.Exception.Message)"
    }
}


# 6. Remove Internet Explorer shortcuts only
# This removes .lnk shortcuts that point to iexplore.exe.
# It does NOT remove Microsoft Edge or uninstall Windows components.
Log "Removing Internet Explorer shortcuts..."

$shortcutLocations = @(
    [Environment]::GetFolderPath("Desktop"),
    [Environment]::GetFolderPath("CommonDesktopDirectory"),
    (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"),
    (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs"),
    (Join-Path $env:APPDATA "Microsoft\Internet Explorer\Quick Launch"),
    (Join-Path $env:APPDATA "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar")
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

$removedIE = 0
$wsh = New-Object -ComObject WScript.Shell

foreach ($location in $shortcutLocations) {
    Get-ChildItem -Path $location -Filter *.lnk -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $shortcut = $wsh.CreateShortcut($_.FullName)
            $target = $shortcut.TargetPath
            if ($target -and ([IO.Path]::GetFileName($target) -ieq "iexplore.exe")) {
                Log "Removing IE shortcut: $($_.FullName)"
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                $removedIE++
            }
        } catch {
            Log "Could not inspect/remove shortcut $($_.FullName): $($_.Exception.Message)"
        }
    }
}

Log "Internet Explorer shortcuts removed: $removedIE"

# 7. Install Yandex
if ($yandexLocal -and (Test-Path $yandexLocal.FullName)) {
    Log "Starting Yandex installer: $($yandexLocal.FullName)"
    try {
        $p = Start-Process -FilePath $yandexLocal.FullName -Wait -PassThru
        Log "Yandex installer finished. ExitCode=$($p.ExitCode)"
    } catch {
        Log "ERROR running Yandex installer: $($_.Exception.Message)"
    }
} else {
    Log "Yandex installer not available."
}

Log "=== PC Installer finished ==="
Add-Type -AssemblyName PresentationFramework
[System.Windows.MessageBox]::Show(
    "Подготовка ПК завершена.`n`nЛог:`n$Log",
    "PC Installer",
    "OK",
    "Information"
) | Out-Null
