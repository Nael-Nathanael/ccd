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

if ($n -le 1) {
    & claude @extra @rest
    exit $LASTEXITCODE
}

$dir = Join-Path $HOME ".claude-profile-$n"

# Ask how a new profile signs in. Regular leaves it to /login. API returns the KEY=VALUE
# lines for ccd.env, once the endpoint answers and its models are listed.
function Read-Auth {
    while ($true) {
        $mode = Read-Host 'Sign in via [1] regular (/login) or [2] API? [1]'
        if ($mode -ne '2') { return '' }
        $url = Read-Host 'Base URL [https://api.anthropic.com]'
        if (-not $url) { $url = 'https://api.anthropic.com' }
        $url = $url.TrimEnd('/')
        $secure = Read-Host 'API key' -AsSecureString
        $key = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
        if (-not $key) { [Console]::Error.WriteLine('ccd: no key given, starting over'); continue }

        [Console]::Error.WriteLine('Testing connection...')
        try {
            $res = Invoke-RestMethod -UseBasicParsing -TimeoutSec 20 -Uri "$url/v1/models?limit=1000" `
                -Headers @{ 'x-api-key' = $key; 'anthropic-version' = '2023-06-01' }
        } catch {
            $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
            [Console]::Error.WriteLine("ccd: connection failed (HTTP $code), starting over")
            continue
        }

        [Console]::Error.WriteLine('Connected.')
        $models = @($res.data | ForEach-Object { $_.id })
        $pick = ''
        if ($models.Count) {
            for ($i = 0; $i -lt $models.Count; $i++) { [Console]::Error.WriteLine("  $($i + 1)) $($models[$i])") }
            $pick = Read-Host 'Default model (number or name, enter to skip)'
            if ($pick -match '^[0-9]+$' -and [int]$pick -ge 1 -and [int]$pick -le $models.Count) { $pick = $models[[int]$pick - 1] }
        }
        $out = "ANTHROPIC_BASE_URL=$url`nANTHROPIC_API_KEY=$key`n"
        if ($pick) { $out += "ANTHROPIC_MODEL=$pick`n" }
        return $out
    }
}

if (-not (Test-Path -LiteralPath $dir)) {
    $apiEnv = ''
    if (-not [Console]::IsInputRedirected) { $apiEnv = Read-Auth }
    [Console]::Error.WriteLine("ccd: creating profile $n in $dir")
    New-Item -ItemType Directory -Path $dir | Out-Null
    if ($apiEnv) { [IO.File]::WriteAllText((Join-Path $dir 'ccd.env'), $apiEnv) }

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
# API profiles keep their endpoint, key and model here. Read as data, never run.
$envFile = Join-Path $dir 'ccd.env'
if (Test-Path -LiteralPath $envFile) {
    foreach ($line in Get-Content -LiteralPath $envFile) {
        $k, $v = $line -split '=', 2
        if ($k -in 'ANTHROPIC_BASE_URL', 'ANTHROPIC_API_KEY', 'ANTHROPIC_MODEL') {
            [Environment]::SetEnvironmentVariable($k, $v)
        }
    }
}
try {
    & claude @extra @rest
} finally {
    # A script shares its environment with the shell that ran it, so put it back.
    foreach ($v in $prev.Keys) { [Environment]::SetEnvironmentVariable($v, $prev[$v]) }
}
exit $LASTEXITCODE
