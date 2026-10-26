# ccd [N] [claude args...] - run Claude Code as profile N. Windows version of `ccd`.
# Profile 1 is plain `claude`. Profile N > 1 is ~\.claude-profile-N: its own login,
# everything else shared with ~\.claude through junctions and symlinks.
$ErrorActionPreference = 'Stop'

$base = Join-Path $HOME '.claude'
$shared = 'projects', 'history.jsonl', 'file-history', 'CLAUDE.md', 'hooks', 'settings.json',
    'plugins', 'skills', 'rules', 'agents', 'commands'

$n = 1
$rest = @($args)
if ($rest.Count -gt 0 -and "$($rest[0])" -match '^[0-9]+$') {
    $n = [int]"$($rest[0])"
    $rest = @($rest | Select-Object -Skip 1)
}
$extra = @("$env:CCD_ARGS" -split '\s+' | Where-Object { $_ })

$reset = $rest.Count -gt 0 -and "$($rest[0])" -eq '--reset-auth'
if ($reset) {
    $rest = @($rest | Select-Object -Skip 1)
    if ($n -le 1) { [Console]::Error.WriteLine('ccd: --reset-auth needs a profile number above 1'); exit 1 }
}

if ($n -le 1) {
    & claude @extra @rest
    exit $LASTEXITCODE
}

$dir = Join-Path $HOME ".claude-profile-$n"

# The model IDs at $url, sent the way Claude Code will send them: both headers. Throws on failure.
function Get-ModelIds($url, $key, $timeout) {
    # Windows PowerShell 5.1 may default to TLS versions api.anthropic.com refuses.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $res = Invoke-RestMethod -UseBasicParsing -TimeoutSec $timeout -Uri "$url/v1/models?limit=1000" `
        -Headers @{ 'x-api-key' = $key; 'Authorization' = "Bearer $key"; 'anthropic-version' = '2023-06-01' }
    if ($res.data -isnot [array]) { throw 'HTTP 200, but not a model list' }
    @($res.data | ForEach-Object { $_.id } | Where-Object { $_ })
}

# Ask how a new profile signs in. Regular leaves it to /login. API returns the key and the
# KEY=VALUE lines for ccd.env (URL and model), once the endpoint answers and its models are listed.
function Read-Auth {
    while ($true) {
        $mode = Read-Host 'Sign in via [1] regular (/login) or [2] API? [1]'
        if ($mode -ne '2') { return $null }
        $url = Read-Host 'Base URL [https://api.anthropic.com]'
        if (-not $url) { $url = 'https://api.anthropic.com' }
        $url = $url.TrimEnd('/') -replace '/v1$', ''
        if ($url -like 'http://*') { [Console]::Error.WriteLine('ccd: warning, http:// sends your key unencrypted') }
        $secure = Read-Host 'API key' -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { $key = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        if (-not $key) { [Console]::Error.WriteLine('ccd: no key given, starting over'); continue }

        [Console]::Error.WriteLine('Testing connection...')
        try {
            # @() because PowerShell unrolls a one-item result into a plain string.
            $models = @(Get-ModelIds $url $key 20)
        } catch {
            $why = if ($_.Exception.Response) { "HTTP $([int]$_.Exception.Response.StatusCode)" } else { $_.Exception.Message }
            [Console]::Error.WriteLine("ccd: connection failed ($why), starting over")
            continue
        }

        [Console]::Error.WriteLine('Connected.')
        $pick = ''
        if ($models.Count) {
            for ($i = 0; $i -lt $models.Count; $i++) { [Console]::Error.WriteLine("  $($i + 1)) $($models[$i])") }
            while ($true) {
                $pick = Read-Host 'Default model (number or name, enter to skip)'
                if ($pick -notmatch '^[0-9]+$') { break }
                if ([int]$pick -ge 1 -and [int]$pick -le $models.Count) { $pick = $models[[int]$pick - 1]; break }
                [Console]::Error.WriteLine("ccd: no model number $pick")
            }
        }
        $out = "ANTHROPIC_BASE_URL=$url`n"
        if ($pick) { $out += "ANTHROPIC_MODEL=$pick`n" }
        return @{ Key = $key; Env = $out }
    }
}

# Only the owner may read a file that holds a key.
function Protect-File($path) {
    & icacls $path /inheritance:r /grant:r "${env:USERNAME}:(R,W)" | Out-Null
}

function Write-Api($api) {
    if (-not $api) { return }
    foreach ($pair in @(@('ccd.key', $api.Key), @('ccd.env', $api.Env))) {
        $file = Join-Path $dir $pair[0]
        [IO.File]::WriteAllText($file, $pair[1])
        Protect-File $file
    }
}

$tty = -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected

# Ask again for a profile that already exists. Regular removes the API files, so /login applies.
if ($reset) {
    if (-not (Test-Path -LiteralPath $dir)) { [Console]::Error.WriteLine("ccd: profile $n does not exist"); exit 1 }
    if (-not $tty) { [Console]::Error.WriteLine('ccd: --reset-auth needs a terminal'); exit 1 }
    $api = Read-Auth
    Remove-Item -LiteralPath (Join-Path $dir 'ccd.key'), (Join-Path $dir 'ccd.env'), (Join-Path $dir 'ccd.models') -ErrorAction SilentlyContinue
    Write-Api $api
}

if (-not (Test-Path -LiteralPath $dir)) {
    $api = $null
    if ($tty) { $api = Read-Auth }
    [Console]::Error.WriteLine("ccd: creating profile $n in $dir")
    New-Item -ItemType Directory -Path $dir | Out-Null
    Write-Api $api

    # User-scope MCP servers live in .claude.json, which is per profile. Seed the new one
    # from whichever of profile 1's files is in use; Claude Code fills in the rest.
    $src = (Join-Path $HOME '.claude.json'), (Join-Path $base '.claude.json') |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Get-Item -Force | Sort-Object LastWriteTime | Select-Object -Last 1
    if ($src) {
        try {
            $mcp = (Get-Content -LiteralPath $src.FullName -Raw | ConvertFrom-Json).mcpServers
            if (-not $mcp) { $mcp = New-Object PSObject }
            # WriteAllText writes UTF-8 without a BOM, which JSON readers expect.
            [IO.File]::WriteAllText((Join-Path $dir '.claude.json'), (@{ mcpServers = $mcp } | ConvertTo-Json -Depth 100))
        } catch {
            [Console]::Error.WriteLine("ccd: could not read $($src.FullName), MCP servers not copied to profile $n")
        }
    }
}

# Every start, so items added to ~\.claude later are picked up.
# Folders become junctions, which need no special rights. Files need a symlink,
# which Windows allows only with Developer Mode on or as administrator.
$unlinked = @()
foreach ($f in $shared) {
    $target = Join-Path $base $f
    $link = Join-Path $dir $f
    if (-not (Test-Path -LiteralPath $target)) { continue }
    if (Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue) { continue }
    if (Test-Path -LiteralPath $target -PathType Container) {
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null
    } else {
        try { New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null }
        catch { $unlinked += $f }
    }
}
if ($unlinked) {
    [Console]::Error.WriteLine("ccd: not shared with profile ${n}: $($unlinked -join ', '). Turn on Developer Mode in Windows Settings to share them.")
}

$prev = @{}
foreach ($v in 'CLAUDE_CONFIG_DIR', 'ANTHROPIC_BASE_URL', 'ANTHROPIC_API_KEY', 'ANTHROPIC_MODEL') {
    $prev[$v] = [Environment]::GetEnvironmentVariable($v)
}
$env:CLAUDE_CONFIG_DIR = $dir
# API profiles keep the key in ccd.key and the URL and model in ccd.env. The key reaches Claude
# Code through apiKeyHelper, so it never sits in the environment of hooks and tools. Variables
# from the parent shell must not override the profile. ccd.env is read as data, never run.
$keyFile = Join-Path $dir 'ccd.key'
if (Test-Path -LiteralPath $keyFile) {
    foreach ($v in 'ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_BASE_URL', 'ANTHROPIC_MODEL') {
        [Environment]::SetEnvironmentVariable($v, $null)
    }
    $envFile = Join-Path $dir 'ccd.env'
    if (Test-Path -LiteralPath $envFile) {
        foreach ($line in Get-Content -LiteralPath $envFile) {
            $k, $v = $line -split '=', 2
            if ($k -in 'ANTHROPIC_BASE_URL', 'ANTHROPIC_MODEL') { [Environment]::SetEnvironmentVariable($k, $v) }
        }
    }
    $helper = "powershell -NoProfile -Command `"Get-Content -Raw -LiteralPath '$keyFile'`""
    $settings = @{ apiKeyHelper = $helper }

    # Claude Code's own gateway discovery keeps only IDs containing "claude" or "anthropic", so
    # ccd lists the server's models in /model itself. Refreshed each start; the last good list
    # is the fallback. ccd.models starts with the URL it came from, so a list from another
    # server is ignored.
    $url = "$env:ANTHROPIC_BASE_URL"
    $modelsFile = Join-Path $dir 'ccd.models'
    if ($url) {
        try {
            $ids = @(Get-ModelIds $url ([IO.File]::ReadAllText($keyFile).Trim()) 3)
            if ($ids.Count) {
                [IO.File]::WriteAllText($modelsFile, ((@($url) + $ids | ForEach-Object { "$_`n" }) -join ''))
                Protect-File $modelsFile
            }
        } catch {}
    }
    $lines = @()
    if (Test-Path -LiteralPath $modelsFile) { $lines = @(Get-Content -LiteralPath $modelsFile) }
    if ($lines.Count -gt 1 -and $lines[0] -eq $url) {
        $rows = @($lines | Select-Object -Skip 1 | Where-Object { $_ } | ForEach-Object { @{ model = $_ } })
        if ($rows.Count) {
            # Built-in rows send Anthropic IDs, which another server may not accept.
            $settings.modelPicker = @{
                replaceBuiltInOptions = $url -ne 'https://api.anthropic.com'
                options = $rows
            }
        }
    }
    # Passed as a file: Windows PowerShell 5.1 strips the quotes from JSON given to a native program.
    $settingsFile = Join-Path $dir 'ccd.settings.json'
    [IO.File]::WriteAllText($settingsFile, (ConvertTo-Json -InputObject $settings -Compress -Depth 5))
    $extra = @('--settings', $settingsFile) + $extra
}
try {
    & claude @extra @rest
} finally {
    # A script shares its environment with the shell that ran it, so put it back.
    foreach ($v in $prev.Keys) { [Environment]::SetEnvironmentVariable($v, $prev[$v]) }
}
exit $LASTEXITCODE
