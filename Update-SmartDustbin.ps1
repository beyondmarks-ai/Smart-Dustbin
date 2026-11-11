[CmdletBinding()]
param(
    [string]$Branch = 'main',
    [string]$AvdName = '',
    [string]$DeviceId = '',
    [string]$PackageId = 'com.example.smart_dustbin',
    [switch]$Release,
    [switch]$Clean,
    [switch]$SkipAnalyze,
    [switch]$SkipTests,
    [switch]$NoPull,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $repoRoot

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$Program,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments
    )
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed ($LASTEXITCODE): $Program $($Arguments -join ' ')"
    }
}

function Find-Tool {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string[]]$Fallbacks = @()
    )
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    foreach ($candidate in $Fallbacks) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }
    throw "Required tool '$Name' was not found. Install it or add it to PATH."
}

function Get-AndroidSdkRoots {
    $roots = @()
    if ($env:ANDROID_SDK_ROOT) { $roots += $env:ANDROID_SDK_ROOT }
    if ($env:ANDROID_HOME) { $roots += $env:ANDROID_HOME }
    if ($env:LOCALAPPDATA) {
        $roots += (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
    }
    return $roots | Where-Object { $_ } | Select-Object -Unique
}

function Get-FlutterAndroidDevices {
    param([string]$Flutter)
    $json = & $Flutter devices --machine
    if ($LASTEXITCODE -ne 0) { throw 'Could not read Flutter devices.' }
    if (-not $json) { return @() }
    $parsedDevices = ConvertFrom-Json -InputObject ($json -join "`n")
    return @($parsedDevices | Where-Object {
        $_.targetPlatform -like 'android-*'
    })
}

function Wait-ForEmulator {
    param(
        [Parameter(Mandatory = $true)][string]$Flutter,
        [Parameter(Mandatory = $true)][string]$Adb,
        [int]$TimeoutSeconds = 240
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $devices = @(Get-FlutterAndroidDevices -Flutter $Flutter)
        $emulator = $devices | Where-Object {
            $_.id -like 'emulator-*' -or $_.name -match '(?i)emulator'
        } | Select-Object -First 1
        if ($null -ne $emulator) {
            $booted = (& $Adb -s $emulator.id shell getprop sys.boot_completed 2>$null).Trim()
            if ($booted -eq '1') { return $emulator }
        }
        Write-Host 'Waiting for the Android emulator to finish booting...'
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)
    throw "The emulator did not become ready within $TimeoutSeconds seconds."
}

Write-Step 'Checking development tools'
$git = Find-Tool -Name 'git'
$flutter = Find-Tool -Name 'flutter'
$sdkRoots = @(Get-AndroidSdkRoots)
$adbFallbacks = @($sdkRoots | ForEach-Object { Join-Path $_ 'platform-tools\adb.exe' })
$emulatorFallbacks = @($sdkRoots | ForEach-Object { Join-Path $_ 'emulator\emulator.exe' })
$adb = Find-Tool -Name 'adb' -Fallbacks $adbFallbacks

Invoke-Checked $git 'rev-parse' '--is-inside-work-tree'
Invoke-Checked $flutter '--version'

$changes = @(& $git status --porcelain --untracked-files=normal)
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the Git working tree.' }

if ($CheckOnly) {
    if ($changes.Count -gt 0) {
        Write-Host 'Local changes are present (a normal update would stop safely):' -ForegroundColor Yellow
        Write-Host ($changes -join "`n") -ForegroundColor Yellow
    }
    Write-Step 'Environment check completed successfully'
    $androidDevices = @(Get-FlutterAndroidDevices -Flutter $flutter)
    if ($androidDevices.Count -eq 0) {
        Write-Host 'No running Android device or emulator was found.' -ForegroundColor Yellow
    } else {
        $androidDevices | ForEach-Object { Write-Host "Android device: $($_.name) [$($_.id)]" }
    }
    exit 0
}

if ($changes.Count -gt 0) {
    Write-Host ($changes -join "`n") -ForegroundColor Yellow
    throw 'Local changes were found. Commit or stash them before updating; nothing was overwritten.'
}

if (-not $NoPull) {
    Write-Step "Pulling the latest origin/$Branch code"
    $currentBranch = (& $git branch --show-current).Trim()
    if ($currentBranch -ne $Branch) {
        throw "Current branch is '$currentBranch'. Switch to '$Branch' before running this updater."
    }
    Invoke-Checked $git 'fetch' 'origin' $Branch
    Invoke-Checked $git 'pull' '--ff-only' 'origin' $Branch
}

Write-Step 'Preparing Flutter dependencies'
if ($Clean) { Invoke-Checked $flutter 'clean' }
Invoke-Checked $flutter 'pub' 'get'
if (-not $SkipAnalyze) { Invoke-Checked $flutter 'analyze' }
if (-not $SkipTests) { Invoke-Checked $flutter 'test' '--no-pub' }

$androidDevices = @(Get-FlutterAndroidDevices -Flutter $flutter)
$selectedDevice = $null
if ($DeviceId) {
    $selectedDevice = $androidDevices | Where-Object { $_.id -eq $DeviceId } | Select-Object -First 1
    if ($null -eq $selectedDevice) {
        throw "Android device '$DeviceId' was not found by Flutter."
    }
} else {
    $selectedDevice = $androidDevices | Where-Object {
        $_.id -like 'emulator-*' -or $_.name -match '(?i)emulator'
    } | Select-Object -First 1
}

if ($null -eq $selectedDevice) {
    Write-Step 'Starting an Android emulator'
    $emulatorTool = Find-Tool -Name 'emulator' -Fallbacks $emulatorFallbacks
    $availableAvds = @(& $emulatorTool -list-avds | Where-Object { $_.Trim() })
    if ($LASTEXITCODE -ne 0 -or $availableAvds.Count -eq 0) {
        throw 'No Android Virtual Device exists. Create one in Android Studio Device Manager first.'
    }
    if (-not $AvdName) { $AvdName = $availableAvds[0].Trim() }
    if ($AvdName -notin $availableAvds) {
        throw "AVD '$AvdName' was not found. Available AVDs: $($availableAvds -join ', ')"
    }
    Write-Host "Launching AVD: $AvdName"
    Start-Process -FilePath $emulatorTool -ArgumentList @('-avd', $AvdName)
    $selectedDevice = Wait-ForEmulator -Flutter $flutter -Adb $adb
}

$buildMode = if ($Release) { 'release' } else { 'debug' }
$androidTarget = $selectedDevice.targetPlatform
if ($androidTarget -notin @('android-arm', 'android-arm64', 'android-x64')) {
    throw "Unsupported Android target '$androidTarget' for $($selectedDevice.name)."
}
Write-Step "Building the $buildMode APK"
Invoke-Checked $flutter 'build' 'apk' "--$buildMode" '--target-platform' $androidTarget

Write-Step "Installing on $($selectedDevice.name) [$($selectedDevice.id)]"
$apkPath = Join-Path $repoRoot "build\app\outputs\flutter-apk\app-$buildMode.apk"
if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf)) {
    throw "The expected APK was not created: $apkPath"
}
Invoke-Checked $adb '-s' $selectedDevice.id 'install' '--no-streaming' '-r' $apkPath

Write-Step 'Launching the updated app'
Invoke-Checked $adb '-s' $selectedDevice.id 'shell' 'am' 'force-stop' $PackageId
Invoke-Checked $adb '-s' $selectedDevice.id 'shell' 'am' 'start' '-n' "$PackageId/.MainActivity"

Write-Host "`nUpdate complete. The latest app is running on $($selectedDevice.name)." -ForegroundColor Green
