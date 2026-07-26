<#
.SYNOPSIS
Install lean-skills into ~/.claude/skills/ (Windows PowerShell).
.DESCRIPTION
Copies the skills next to this script into the Claude Code personal skills
directory, prompting before overwriting an existing skill.
Set CLAUDE_SKILLS_DIR to target somewhere else.
Upgrading across versions that renamed or removed a skill: -Uninstall, then install.
.PARAMETER Yes
Overwrite existing skills without prompting.
.PARAMETER Uninstall
Remove exactly this collection's skills from the target; everything else is left alone.
.EXAMPLE
.\install.ps1 -Yes
#>
[CmdletBinding()]
param([switch]$Yes, [switch]$Uninstall)

$ErrorActionPreference = 'Stop'

$src = Join-Path $PSScriptRoot 'skills'
if (-not (Test-Path -LiteralPath $src)) { throw "skills/ not found next to this script" }
$srcAbs = ([IO.Path]::GetFullPath($src)).TrimEnd('\')

# Snapshot the source list before touching the target: if anything ever lands
# inside the source, it must not be picked up as a tenth skill and copied into itself.
$srcDirs = @(Get-ChildItem -Directory -LiteralPath $srcAbs)

# No set-but-empty check here, unlike install.sh: Windows drops empty environment
# variables outright, so an empty CLAUDE_SKILLS_DIR is indistinguishable from an
# unset one and the default below is the only sensible reading.
$dest = if ($env:CLAUDE_SKILLS_DIR) { $env:CLAUDE_SKILLS_DIR } else { Join-Path $HOME '.claude\skills' }

# Track the directories we create, deepest first, so a refused run unwinds exactly
# what it made and never touches a directory that already held something.
$createdLevels = @()
if (-not (Test-Path -LiteralPath $dest)) {
  if ($Uninstall) { Write-Host "nothing installed at $dest"; exit 0 }
  $probeUp = ([IO.Path]::GetFullPath($dest)).TrimEnd('\')
  while ($probeUp -and -not (Test-Path -LiteralPath $probeUp)) {
    $createdLevels += $probeUp
    $probeUp = [IO.Path]::GetDirectoryName($probeUp)
  }
  # .NET rather than New-Item: Windows PowerShell 5.1's New-Item has no
  # -LiteralPath, and -Path would treat [ ] in a path as a wildcard.
  [IO.Directory]::CreateDirectory($dest) | Out-Null
}
$destAbs = ([IO.Path]::GetFullPath($dest)).TrimEnd('\')

function Undo-Created {
  foreach ($lvl in $createdLevels) {
    if (Test-Path -LiteralPath $lvl) {
      if (-not (Get-ChildItem -Force -LiteralPath $lvl)) {
        Remove-Item -Force -LiteralPath $lvl -ErrorAction SilentlyContinue
      }
    }
  }
}
function Deny-Target { Undo-Created; throw "refusing: target $destAbs is the source (or aliases it)" }

# Guard in two layers. The prefix comparison is free and catches ordinary paths;
# the probe is filesystem truth — it survives junctions, symlinks (including
# chained ones and links on parent components), and case-folding, because it asks
# "does a file I just wrote into the target appear inside the source?" instead of
# trying to canonicalise names. GetFullPath resolves 8.3 names but no reparse points.
if (($destAbs + '\').StartsWith($srcAbs + '\', [StringComparison]::OrdinalIgnoreCase)) { Deny-Target }
if (($srcAbs + '\').StartsWith($destAbs + '\', [StringComparison]::OrdinalIgnoreCase)) { Deny-Target }

$canary = ".lean-skills-canary-$PID"
$canaryPath = Join-Path $srcAbs $canary
$aliased = $false
try {
  [IO.File]::WriteAllText($canaryPath, '')
  # Walk up from the target and ask the filesystem, at each level, whether the
  # source's canary is visible there. Reads traverse junctions and symlinks, so
  # this catches a link that lands on the source itself *and* one that lands
  # somewhere beneath it — which a marker written into the target cannot.
  $up = $destAbs
  for ($i = 0; $i -lt 64 -and $up; $i++) {
    if (Test-Path -LiteralPath (Join-Path $up $canary)) { $aliased = $true; break }
    $up = [IO.Path]::GetDirectoryName($up)
  }
} finally {
  Remove-Item -Force -LiteralPath $canaryPath -ErrorAction SilentlyContinue
}
if ($aliased) { Deny-Target }

# Separately confirm the target is writable, so a permission problem surfaces
# here rather than halfway through the copy.
$probePath = Join-Path $destAbs ".lean-skills-probe-$PID"
try { [IO.File]::WriteAllText($probePath, '') }
catch { Undo-Created; throw "cannot write to target $destAbs" }
Remove-Item -Force -LiteralPath $probePath -ErrorAction SilentlyContinue

if ($Uninstall) {
  $removed = 0
  foreach ($dir in $srcDirs) {
    $target = Join-Path $destAbs $dir.Name
    if (Test-Path -LiteralPath $target) {
      Remove-Item -Recurse -Force -LiteralPath $target
      Write-Host "  removed   $($dir.Name)"
      $removed++
    }
  }
  Write-Host ""
  Write-Host "$removed removed from $destAbs - only this collection's skills; anything else was left alone."
  exit 0
}

$installed = 0
$kept = 0

foreach ($dir in $srcDirs) {
  $target = Join-Path $destAbs $dir.Name
  if (Test-Path -LiteralPath $target) {
    if (-not $Yes) {
      # Read-Host throws under -NonInteractive; treat that as "keep it".
      try { $reply = Read-Host "overwrite existing $($dir.Name)? [y/N]" } catch { $reply = '' }
      if ($reply -notmatch '^[yY]') {
        Write-Host "  kept      $($dir.Name)"
        $kept++
        continue
      }
    }
  }
  # Copy beside the target first, then swap, so an interrupted copy leaves the
  # previously installed skill intact instead of a half-written one.
  $staging = Join-Path $destAbs ".lean-skills-staging-$PID"
  if (Test-Path -LiteralPath $staging) { Remove-Item -Recurse -Force -LiteralPath $staging }
  Copy-Item -Recurse -LiteralPath $dir.FullName -Destination $staging
  if (Test-Path -LiteralPath $target) { Remove-Item -Recurse -Force -LiteralPath $target }
  Move-Item -LiteralPath $staging -Destination $target
  Write-Host "  installed $($dir.Name)"
  $installed++
}

Write-Host ""
Write-Host "$installed installed, $kept kept -> $destAbs"
Write-Host "Restart your Claude Code session to pick them up. Remove later with -Uninstall."
Write-Host ""
Write-Host "Resident (model-invoked): verification-before-completion, receiving-code-review,"
Write-Host "                          diagnosing-bugs, code-review, resolving-merge-conflicts"
Write-Host "Manual (user-invoked):    grill-me, implement, tdd, worktree"
