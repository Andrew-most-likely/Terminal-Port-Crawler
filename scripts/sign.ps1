<#
.SYNOPSIS
    Code-signs dist\tpc.exe with signtool so Windows SmartScreen trusts it.

.DESCRIPTION
    This only helps once you actually hold a code-signing certificate:
      - An EV (Extended Validation) cert gets instant SmartScreen reputation.
      - A standard OV cert is signed but SmartScreen still has to build up
        reputation for it over time/downloads before the warning disappears.
      - Microsoft Trusted Signing (Azure) is a low-cost subscription option
        that also gets fast reputation; it signs via `az trustedsigning` /
        the Trusted Signing dialog instead of a local .pfx, so it isn't
        wired into this script.
    A self-signed certificate will NOT remove the warning for anyone but you
    (see scripts/self-trust.ps1) - it's only useful for local testing.

.PARAMETER PfxPath
    Path to your .pfx code-signing certificate file.

.PARAMETER Thumbprint
    Alternative to -PfxPath: SHA1 thumbprint of a cert already installed in
    your Windows certificate store (Cert:\CurrentUser\My).

.PARAMETER ExePath
    Path to the executable to sign. Defaults to dist\tpc.exe.

.EXAMPLE
    ./scripts/sign.ps1 -PfxPath C:\certs\tpc-codesign.pfx

.EXAMPLE
    ./scripts/sign.ps1 -Thumbprint AA11BB22CC33DD44EE55FF6677889900AABBCCDD
#>
param(
    [string]$PfxPath,
    [string]$Thumbprint,
    [string]$ExePath = "$PSScriptRoot\..\dist\tpc.exe",
    [string]$TimestampUrl = "http://timestamp.digicert.com"
)

$ErrorActionPreference = "Stop"

if (-not $PfxPath -and -not $Thumbprint) {
    Write-Error "Pass either -PfxPath <file.pfx> or -Thumbprint <cert-thumbprint>."
    exit 1
}

if (-not (Test-Path $ExePath)) {
    Write-Error "Executable not found: $ExePath (build it first with pyinstaller tpc.spec)"
    exit 1
}

# Locate signtool.exe from the Windows SDK
$signtool = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin" -Recurse -Filter "signtool.exe" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -like "*x64*" } |
    Select-Object -First 1 -ExpandProperty FullName

if (-not $signtool) {
    Write-Error "signtool.exe not found. Install the Windows SDK (or the 'Windows 10/11 SDK' component of Visual Studio Build Tools)."
    exit 1
}

$signArgs = @("sign", "/fd", "sha256", "/tr", $TimestampUrl, "/td", "sha256")

if ($PfxPath) {
    if (-not (Test-Path $PfxPath)) {
        Write-Error "PFX not found: $PfxPath"
        exit 1
    }
    $securePwd = Read-Host "PFX password" -AsSecureString
    $plainPwd = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd)
    )
    $signArgs += @("/f", $PfxPath, "/p", $plainPwd)
} else {
    $signArgs += @("/sha1", $Thumbprint)
}

$signArgs += $ExePath

Write-Host "Signing $ExePath ..."
& $signtool @signArgs

if ($LASTEXITCODE -ne 0) {
    Write-Error "signtool failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host "Verifying signature ..."
& $signtool verify /pa /v $ExePath

Write-Host "`nDone. Note: even a validly signed exe can still trip SmartScreen/AV" -ForegroundColor Yellow
Write-Host "heuristics for security tools (port scanners are commonly flagged" -ForegroundColor Yellow
Write-Host "as 'HackTool'/'PUA'). If that happens, submit the signed file at" -ForegroundColor Yellow
Write-Host "https://www.microsoft.com/wdsi/filesubmission for reputation review." -ForegroundColor Yellow
