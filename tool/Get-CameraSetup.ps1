[CmdletBinding()]
param(
    [string]$Port,
    [ValidateRange(5, 180)][int]$TimeoutSeconds = 60,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

function Read-SetupReply([string]$Text) {
    $codeMatches = [regex]::Matches($Text, 'Camera (?:location )?setup code:\s*([a-fA-F0-9]{32})')
    $ipMatches = [regex]::Matches($Text, '(?:Camera IP:\s*|(?:EcoSort camera URL:|WiFi connected:)\s*http://)(\d{1,3}(?:\.\d{1,3}){3})')
    $codeValue = $null
    $ipValue = $null
    if ($codeMatches.Count -gt 0) { $codeValue = $codeMatches[$codeMatches.Count - 1].Groups[1].Value }
    if ($ipMatches.Count -gt 0) {
        $candidate = $ipMatches[$ipMatches.Count - 1].Groups[1].Value
        $parsed = $null
        if ([System.Net.IPAddress]::TryParse($candidate, [ref]$parsed) -and $candidate -ne '0.0.0.0') {
            $ipValue = $candidate
        }
    }
    [pscustomobject]@{ IP = $ipValue; SetupCode = $codeValue }
}

if ($SelfTest) {
    $fixtureCode = '0123456789abcdef0123456789abcdef'
    $boot = Read-SetupReply "Camera location setup code: $fixtureCode`nEcoSort camera URL: http://10.1.2.3/ | captures=1"
    $query = Read-SetupReply "Camera setup code: $fixtureCode`nCamera IP: 192.168.4.1 (recovery)"
    $bad = Read-SetupReply 'Camera IP: 999.999.999.999'
    if ($boot.IP -ne '10.1.2.3' -or $boot.SetupCode -ne $fixtureCode -or
        $query.IP -ne '192.168.4.1' -or $query.SetupCode -ne $fixtureCode -or $bad.IP) {
        throw 'Camera setup parser self-test failed'
    }
    Write-Output 'Parser self-tests passed (boot log, direct query, recovery IP, invalid IP).'
    exit 0
}

$ports = @([System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object)
if (!$Port) {
    if ($ports.Count -eq 0) { throw 'No USB serial port found. Connect the Uno/USB adapter to the computer.' }
    if ($ports.Count -gt 1) { throw ('Multiple serial ports found: ' + ($ports -join ', ') + '. Run with -Port COM3 (or the correct camera port).') }
    $Port = $ports[0]
}
if ($ports -notcontains $Port) { throw "Serial port $Port is not available. Available: $($ports -join ', ')" }

$serial = [System.IO.Ports.SerialPort]::new($Port, 115200, 'None', 8, 'One')
$serial.DtrEnable = $false
$serial.RtsEnable = $false
$serial.ReadTimeout = 500
$serial.WriteTimeout = 1000
$buffer = ''
$reply = $null
try {
    try { $serial.Open() } catch { throw "Cannot open $Port. Close Arduino Serial Monitor/Plotter or other serial tools, then retry. $($_.Exception.Message)" }
    Write-Host "Reading camera details from $Port (115200 baud). No Arduino Serial Monitor required."
    Write-Host 'Leave ESP32 GPIO0 disconnected from GND; keep Uno RESET grounded.'
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $nextQuery = [DateTime]::MinValue
    $fallbackAt = [DateTime]::UtcNow.AddSeconds(4)
    $prompted = $false
    while ([DateTime]::UtcNow -lt $deadline) {
        if ([DateTime]::UtcNow -ge $nextQuery) {
            $serial.Write('i')
            $nextQuery = [DateTime]::UtcNow.AddSeconds(2)
        }
        $buffer += $serial.ReadExisting()
        if ($buffer.Length -gt 32768) { $buffer = $buffer.Substring($buffer.Length - 16384) }
        $parsedReply = Read-SetupReply $buffer
        if (!$reply) { $reply = $parsedReply }
        else {
            if ($parsedReply.IP) { $reply.IP = $parsedReply.IP }
            if ($parsedReply.SetupCode) { $reply.SetupCode = $parsedReply.SetupCode }
        }
        if ($reply.IP -and $reply.SetupCode) { break }
        if (!$prompted -and [DateTime]::UtcNow -ge $fallbackAt) {
            Write-Host 'No complete reply yet. For older firmware, press the ESP32-CAM reset button once now. Keep its hotspot enabled.'
            $prompted = $true
        }
        Start-Sleep -Milliseconds 100
    }
} finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
}

if (!$reply -or !$reply.SetupCode) { throw 'No setup code received. Check Uno/ESP32 serial wiring and reset the ESP32 while this script is running. Do not ground GPIO0.' }
if (!$reply.IP) {
    Write-Host "Camera setup code: $($reply.SetupCode)"
    throw 'Camera has no IP yet. Enable its hotspot or wait for recovery, then run again.'
}
Write-Host ''
Write-Host "Camera IP:         $($reply.IP)"
Write-Host "Camera URL:        http://$($reply.IP)/"
Write-Host "Camera setup code: $($reply.SetupCode)"
Write-Host 'Keep the setup code private. Paste the IP and full code into EcoSort camera settings.'
Write-Host 'No credentials were written to a file.'
