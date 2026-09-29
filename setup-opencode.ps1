# =============================================================================
#  OpenCode workshop setup (Windows 10/11, native, no admin rights needed)
#
#  Installs OpenCode and configures it to use an OpenRouter endpoint.
#  Run from PowerShell in the folder where you saved this file:
#
#     powershell -ExecutionPolicy Bypass -File .\setup-opencode.ps1
#
#  Safe to run more than once. An existing OpenCode config is backed up first.
# =============================================================================

# ---- FACILITATORS: fill in these values before handing the script out -------

# OpenRouter API base URL. The public endpoint is https://openrouter.ai/api/v1
$OpenRouterBaseUrl = "REPLACE_WITH_OPENROUTER_ENDPOINT_URL"

# OpenRouter API key. Leave the placeholder to make the script ask each
# participant for their own key (recommended), or paste a shared key here.
$OpenRouterApiKey = "REPLACE_WITH_OPENROUTER_API_KEY"

# Main coding model: OpenRouter model ID exactly as shown on openrouter.ai,
# e.g. "vendor/model-name"
$OpenCodeModel = "REPLACE_WITH_OPENROUTER_MODEL_ID"

# Small model for light background tasks such as naming sessions.
# Leave the placeholder to use the main model for these too.
$OpenCodeSmallModel = "REPLACE_WITH_OPENROUTER_SMALL_MODEL_ID"

# Only route to OpenRouter providers serving the model at these precisions
# (comma-separated). Match what you will self-host later.
$OpenRouterPrecisions = "bf16,fp16"

# OpenCode version to install, e.g. "1.18.33". Empty = latest release.
# Pin a version so every participant runs the same build.
$OpenCodeVersion = ""

# ---- nothing below needs editing -------------------------------------------

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # makes downloads much faster in Windows PowerShell 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$ConfigDir  = Join-Path (Join-Path $HOME ".config") "opencode"
$ConfigFile = Join-Path $ConfigDir "opencode.json"
$KeyFile    = Join-Path $ConfigDir "openrouter.key"
$BinDir     = Join-Path (Join-Path $HOME ".opencode") "bin"
$Utf8NoBom  = New-Object System.Text.UTF8Encoding $false

function Write-Info([string]$m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok([string]$m)   { Write-Host " ok $m" -ForegroundColor Green }
function Stop-Setup([string]$m) { Write-Host "error: $m" -ForegroundColor Red; exit 1 }
function Test-Placeholder([string]$v) { return ([string]::IsNullOrWhiteSpace($v) -or $v.StartsWith("REPLACE_WITH_")) }
function ConvertTo-JsonText([string]$v) { return $v.Replace('\', '\\').Replace('"', '\"') }

# 1. Check the settings and the machine -------------------------------------
Write-Info "Checking settings and prerequisites"

if (Test-Placeholder $OpenRouterBaseUrl) { Stop-Setup "OpenRouterBaseUrl is not set. Ask the facilitator for an updated script." }
if (Test-Placeholder $OpenCodeModel)     { Stop-Setup "OpenCodeModel is not set. Ask the facilitator for an updated script." }
if (-not $OpenRouterBaseUrl.StartsWith("https://")) { Stop-Setup "OpenRouterBaseUrl must start with https:// (got: $OpenRouterBaseUrl)" }
$OpenRouterBaseUrl = $OpenRouterBaseUrl.TrimEnd("/")
if (Test-Placeholder $OpenCodeSmallModel) { $OpenCodeSmallModel = $OpenCodeModel }
$precisionList = @($OpenRouterPrecisions -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($precisionList.Count -eq 0) { Stop-Setup "OpenRouterPrecisions is empty. Use e.g. `"bf16,fp16`"." }

$arch = $env:PROCESSOR_ARCHITECTURE
if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }   # 32-bit PowerShell on 64-bit Windows
switch ($arch) {
    "AMD64" { $target = "windows-x64" }
    "ARM64" { $target = "windows-arm64" }
    default { Stop-Setup "Unsupported processor architecture: $arch" }
}

# Older x64 CPUs without AVX2 need the "baseline" build (same check as the official installer).
if ($target -eq "windows-x64") {
    try {
        if (-not ("OpenCodeSetup.Cpu" -as [type])) {
            Add-Type -Namespace OpenCodeSetup -Name Cpu -MemberDefinition '[DllImport("kernel32.dll")] public static extern bool IsProcessorFeaturePresent(int f);'
        }
        if (-not [OpenCodeSetup.Cpu]::IsProcessorFeaturePresent(40)) { $target = "windows-x64-baseline" }
    } catch {
        Write-Host "    note: could not check for AVX2 support; using the standard x64 build."
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "    note: Git is not installed. You will need it in the workshop: winget install --id Git.Git -e"
}
Write-Ok "Windows $arch, build: $target"

# 2. Get the API key -----------------------------------------------------------
if (Test-Placeholder $OpenRouterApiKey) {
    $secure = Read-Host "Paste your OpenRouter API key (input is hidden) and press Enter" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $OpenRouterApiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}
$OpenRouterApiKey = ($OpenRouterApiKey -replace '\s', '')
if ([string]::IsNullOrEmpty($OpenRouterApiKey)) { Stop-Setup "No API key given." }

# 3. Install OpenCode ----------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($OpenCodeVersion)) {
    $url = "https://github.com/anomalyco/opencode/releases/latest/download/opencode-$target.zip"
    Write-Info "Installing OpenCode (latest)"
} else {
    $v = $OpenCodeVersion.TrimStart("v")
    $url = "https://github.com/anomalyco/opencode/releases/download/v$v/opencode-$target.zip"
    Write-Info "Installing OpenCode $v"
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("opencode-setup-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    $zip = Join-Path $tmp "opencode.zip"
    try { Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing }
    catch { Stop-Setup "Download failed from $url. Check the version number and your network or proxy. ($($_.Exception.Message))" }

    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $exe = Get-ChildItem -Path $tmp -Filter "opencode.exe" -Recurse | Select-Object -First 1
    if (-not $exe) { Stop-Setup "opencode.exe was not found in the download." }

    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    try { Copy-Item -Path $exe.FullName -Destination (Join-Path $BinDir "opencode.exe") -Force }
    catch { Stop-Setup "Could not replace opencode.exe. Close any running OpenCode window and run the script again." }
} finally {
    Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# Add the install folder to your user PATH (no admin rights needed).
$envKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $true)
$userPath = [string]$envKey.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
$envKey.Close()
if (($userPath -split ";") -notcontains $BinDir) {
    $newPath = (($userPath.TrimEnd(";"), $BinDir) | Where-Object { $_ }) -join ";"
    $envKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $true)
    $envKey.SetValue("Path", $newPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
    $envKey.Close()
    # Tell Windows the environment changed, so new terminals see the new PATH.
    [Environment]::SetEnvironmentVariable("OPENCODE_SETUP_TMP", "1", "User")
    [Environment]::SetEnvironmentVariable("OPENCODE_SETUP_TMP", $null, "User")
}
$env:Path = "$BinDir;$env:Path"

$installed = ""
try { $installed = & (Join-Path $BinDir "opencode.exe") --version } catch { }
Write-Ok "OpenCode $installed installed in $BinDir"

# 4. Write the configuration --------------------------------------------------
Write-Info "Writing configuration to $ConfigDir"
New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
foreach ($name in @("opencode.json", "opencode.jsonc")) {
    $existing = Join-Path $ConfigDir $name
    if (Test-Path $existing) {
        Move-Item -Path $existing -Destination "$existing.bak-$stamp" -Force
        Write-Host "    backed up $existing.bak-$stamp"
    }
}

# The key lives in its own file, readable only by you.
[IO.File]::WriteAllText($KeyFile, $OpenRouterApiKey, $Utf8NoBom)
try {
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls.exe $KeyFile /inheritance:r /grant:r "${me}:(R,W)" | Out-Null
} catch {
    Write-Host "    note: could not restrict permissions on $KeyFile"
}

$m = ConvertTo-JsonText $OpenCodeModel
$s = ConvertTo-JsonText $OpenCodeSmallModel
$u = ConvertTo-JsonText $OpenRouterBaseUrl
$q = ($precisionList | ForEach-Object { '"' + (ConvertTo-JsonText $_) + '"' }) -join ", "

# Routing rules sent to OpenRouter with every request for these models:
# only the chosen precisions, and only providers that don't store or train on data.
function Get-ModelEntry([string]$id) {
    return @"
        "$id": {
          "options": {
            "provider": {
              "quantizations": [$q],
              "data_collection": "deny"
            }
          }
        }
"@
}
if ($s -eq $m) {
    $modelsJson = Get-ModelEntry $m
    $whitelistJson = "`"$m`""
} else {
    $modelsJson = (Get-ModelEntry $m) + ",`n" + (Get-ModelEntry $s)
    $whitelistJson = "`"$m`", `"$s`""
}

$json = @"
{
  "`$schema": "https://opencode.ai/config.json",
  "model": "openrouter/$m",
  "small_model": "openrouter/$s",
  "enabled_providers": ["openrouter"],
  "provider": {
    "openrouter": {
      "options": {
        "baseURL": "$u",
        "apiKey": "{file:~/.config/opencode/openrouter.key}"
      },
      "models": {
$modelsJson
      },
      "whitelist": [$whitelistJson]
    }
  },
  "share": "disabled",
  "autoupdate": false
}
"@
[IO.File]::WriteAllText($ConfigFile, $json, $Utf8NoBom)
Write-Ok "Configuration written"

# 5. Done ----------------------------------------------------------------------
Write-Host ""
Write-Host " OpenCode is installed and configured." -ForegroundColor Green
Write-Host ""
Write-Host "   Model:        openrouter/$OpenCodeModel"
Write-Host "   Small model:  openrouter/$OpenCodeSmallModel"
Write-Host "   Precision:    $($precisionList -join ', ')"
Write-Host "   Endpoint:     $OpenRouterBaseUrl"
Write-Host "   Config:       $ConfigFile"
Write-Host ""
Write-Host " Next: open a NEW terminal window (so PATH is updated), then run:"
Write-Host ""
Write-Host '   opencode run "Reply with the single word: ready"'
Write-Host ""
Write-Host " If it replies, you're done. Start OpenCode in a project folder with:  opencode"
Write-Host ""
