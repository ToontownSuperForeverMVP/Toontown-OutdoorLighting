# Install the portable modules into an existing Toontown checkout.
#
# The script is deliberately path-based: it does not clone a game or install
# Panda3D. SourceRoot must be the folder that contains the ``toontown`` package.
# On conflicts it stops by default; -Force first copies each replaced file into
# a timestamped backup tree. Playground hooks are edited only when both standard
# enter/exit insertion points can be identified, and the whole file is backed up
# before the first hook write.
param(
    [Parameter(Mandatory = $true, Position = 0)] [string] $SourceRoot,
    [switch] $Force,
    [switch] $SkipPlaygroundHooks
)

$ErrorActionPreference = 'Stop'
# Resolve once so every subsequent target/backup path is rooted in the checkout.
$SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$PackageRoot = $PSScriptRoot
$RequiredFiles = @('OutdoorLighting.py', 'ProceduralSky.py', 'LightingConfig.py', 'SkyUtil.py')
foreach ($Name in $RequiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $PackageRoot $Name) -PathType Leaf)) { throw "Package file missing: $Name" }
}

$HoodDir = Join-Path $SourceRoot 'toontown\hood'
if (-not (Test-Path -LiteralPath $HoodDir -PathType Container)) { throw "Couldn't find toontown\hood under '$SourceRoot'. Pass the repository root (the folder containing toontown)." }
$ToontownDir = Split-Path -Parent $HoodDir
$ShaderDir = Join-Path $ToontownDir 'shaders'
if (-not (Test-Path -LiteralPath $ShaderDir -PathType Container)) { New-Item -ItemType Directory -Path $ShaderDir -Force | Out-Null }

$BackupDir = Join-Path $SourceRoot ('.outdoorlighting-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$Changed = [System.Collections.Generic.List[string]]::new()
$BackedUp = [System.Collections.Generic.List[string]]::new()
function Get-RepoRelativePath([string] $Path) { return $Path.Substring($SourceRoot.Length).TrimStart([char[]]@('\', '/')) }

# Preserve the original relative layout under one backup directory. This lets a
# developer restore a single file or the full hook edit without guessing which
# package version was replaced.
function Backup-File([string] $Path) {
    $relative = Get-RepoRelativePath $Path
    $backupPath = Join-Path $BackupDir $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $backupPath) -Force | Out-Null
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    $BackedUp.Add($relative)
}
function Install-File([string] $From, [string] $To) {
    if (Test-Path -LiteralPath $To -PathType Leaf) {
        $same = (Get-FileHash -LiteralPath $From -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $To -Algorithm SHA256).Hash
        if ($same) { return }
        if (-not $Force) { throw "Target already has a different '$(Get-RepoRelativePath $To)'. Re-run with -Force to back it up and replace it." }
        Backup-File $To
    }
    Copy-Item -LiteralPath $From -Destination $To -Force
    $Changed.Add((Get-RepoRelativePath $To))
}

# Python modules live beside Hood.py; shaders live under toontown/shaders because
# OutdoorLighting resolves that location in addition to its packaged fallback.
foreach ($Name in $RequiredFiles) { Install-File (Join-Path $PackageRoot $Name) (Join-Path $HoodDir $Name) }
foreach ($Shader in Get-ChildItem -LiteralPath (Join-Path $PackageRoot 'shaders') -File -Filter '*.glsl') { Install-File $Shader.FullName (Join-Path $ShaderDir $Shader.Name) }

if (-not $SkipPlaygroundHooks) {
    $Playground = Join-Path $ToontownDir 'safezone\Playground.py'
    if (Test-Path -LiteralPath $Playground -PathType Leaf) {
        $source = [System.IO.File]::ReadAllText($Playground)
        if ($source -notmatch 'OutdoorLighting\.begin\s*\(') {
            $enterPattern = '(?m)^(?<indent>[\t ]*)self\.loader\.geom\.reparentTo\((?:base\.)?render\)[\t ]*$'
            $exitPattern = '(?m)^(?<indent>[\t ]*)self\.loader\.geom\.reparentTo\((?:base\.)?hidden\)[\t ]*$'
            if (-not [regex]::IsMatch($source, $enterPattern) -or -not [regex]::IsMatch($source, $exitPattern)) { throw "Found Playground.py but couldn't identify its geometry entry/exit hooks. Files are installed; integrate begin()/end() manually using README.md." }
            $enterLines = @(
                '{0}try:',
                '{0}    from toontown.hood import OutdoorLighting',
                "{0}    _lightingHood = getattr(self.loader, 'hood', None)",
                "{0}    OutdoorLighting.begin(self.loader.geom, hoodId=getattr(_lightingHood, 'hoodId', getattr(_lightingHood, 'id', None)), zoneId=requestStatus.get('zoneId'))",
                "{0}except Exception as _lightingError:",
                "{0}    self.notify.warning('Unable to start outdoor lighting: %s' % _lightingError)"
            )
            $exitLines = @(
                '{0}try:',
                '{0}    from toontown.hood import OutdoorLighting',
                '{0}    OutdoorLighting.end(self.loader.geom)',
                '{0}except Exception as _lightingError:',
                "{0}    self.notify.warning('Unable to stop outdoor lighting: %s' % _lightingError)"
            )
            # Insert after geometry enters render and before it returns to hidden;
            # the paired calls acquire/release the shared lighting rig per zone.
            $source = [regex]::Replace($source, $enterPattern, { param($m) $m.Value + "`r`n" + [string]::Join("`r`n", ($enterLines | ForEach-Object { $_ -f $m.Groups['indent'].Value })) }, 1)
            $source = [regex]::Replace($source, $exitPattern, { param($m) [string]::Join("`r`n", ($exitLines | ForEach-Object { $_ -f $m.Groups['indent'].Value })) + "`r`n" + $m.Value }, 1)
            Backup-File $Playground
            [System.IO.File]::WriteAllText($Playground, $source, [System.Text.UTF8Encoding]::new($false))
            $Changed.Add((Get-RepoRelativePath $Playground))
        }
    }
}

Write-Host "OutdoorLighting installed into '$SourceRoot'."
Write-Host "Python modules: $HoodDir"
Write-Host "GLSL shaders:  $ShaderDir"
if ($BackedUp.Count) { Write-Host "Backups:        $BackupDir" }
if (-not $Changed.Count) { Write-Host 'Everything was already installed and up to date.' } else { Write-Host ("Updated {0} file(s)." -f $Changed.Count) }
if ($SkipPlaygroundHooks) { Write-Host 'Playground hooks skipped; see README.md for manual begin/end calls.' } else { Write-Host 'Outdoor playground begin/end hooks were added when standard entry points were found.' }
