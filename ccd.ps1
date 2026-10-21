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

if (-not (Test-Path -LiteralPath $dir)) {
    [Console]::Error.WriteLine("ccd: creating profile $n in $dir")
    New-Item -ItemType Directory -Path $dir | Out-Null

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

$prev = $env:CLAUDE_CONFIG_DIR
$env:CLAUDE_CONFIG_DIR = $dir
try {
    & claude @extra @rest
} finally {
    # A script shares its environment with the shell that ran it, so put it back.
    $env:CLAUDE_CONFIG_DIR = $prev
}
exit $LASTEXITCODE
