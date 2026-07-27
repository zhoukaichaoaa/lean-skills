<#
.SYNOPSIS
Install lean-skills into ~/.claude/skills/ (Windows PowerShell).
.DESCRIPTION
Copies the skills next to this script into the Claude Code personal skills
directory, prompting before overwriting an existing skill.
Set CLAUDE_SKILLS_DIR to an absolute path to target somewhere else.
.PARAMETER Yes
Overwrite existing skills without prompting.
.PARAMETER Adopt
Also take over same-named directories that carry no ownership marker. This is
how you upgrade from a version before 0.7.0, which did not write markers.
.PARAMETER Uninstall
Remove this collection's skills from the target.
.EXAMPLE
.\install.ps1 -Yes
.EXAMPLE
.\install.ps1 -Yes -Adopt
#>
[CmdletBinding()]
param([switch]$Yes, [switch]$Adopt, [switch]$Uninstall)

$ErrorActionPreference = 'Stop'

$src = Join-Path $PSScriptRoot 'skills'
if (-not (Test-Path -LiteralPath $src)) { throw "skills/ not found next to this script" }
$srcAbs = ([IO.Path]::GetFullPath($src)).TrimEnd('\')

# Snapshot the source list before touching the target: if anything ever lands
# inside the source, it must not be picked up as a tenth skill and copied into itself.
$srcDirs = @(Get-ChildItem -Directory -LiteralPath $srcAbs)

# A blank or relative CLAUDE_SKILLS_DIR causes the same harm: writing somewhere
# the caller did not mean. (Windows drops empty environment variables outright,
# so the set-but-empty case install.sh guards against cannot arise here.)
if ($env:CLAUDE_SKILLS_DIR) {
  if (-not $env:CLAUDE_SKILLS_DIR.Trim()) { throw "CLAUDE_SKILLS_DIR is blank" }
  if (-not [IO.Path]::IsPathRooted($env:CLAUDE_SKILLS_DIR)) {
    throw "CLAUDE_SKILLS_DIR must be an absolute path (got: '$env:CLAUDE_SKILLS_DIR')"
  }
}
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
    if ((Test-Path -LiteralPath $lvl) -and -not (Get-ChildItem -Force -LiteralPath $lvl)) {
      Remove-Item -Force -LiteralPath $lvl -ErrorAction SilentlyContinue
    }
  }
}
function Deny-Target { Undo-Created; throw "refusing: target $destAbs is the source (or aliases it)" }

# Walk up from $from looking for $name. Reads traverse junctions and symlinks,
# so a canary seen from the other side proves aliasing that GetFullPath cannot
# reveal — it resolves 8.3 names but no reparse points.
function Test-CanarySeenFrom($from, $name) {
  $up = $from
  for ($i = 0; $i -lt 64 -and $up; $i++) {
    if (Test-Path -LiteralPath (Join-Path $up $name)) { return $true }
    $up = [IO.Path]::GetDirectoryName($up)
  }
  return $false
}

# Guard in three layers: free prefix comparisons both ways, then a canary in
# each direction. One walk cannot cover both — a canary in the source is *below*
# a target that contains it, and walking up would never reach it.
if (($destAbs + '\').StartsWith($srcAbs + '\', [StringComparison]::OrdinalIgnoreCase)) { Deny-Target }
if (($srcAbs + '\').StartsWith($destAbs + '\', [StringComparison]::OrdinalIgnoreCase)) { Deny-Target }

$canary = ".lean-skills-canary-$PID"

# Is the target the source, or inside it?
$aliased = $false
try {
  [IO.File]::WriteAllText((Join-Path $srcAbs $canary), '')
  $aliased = Test-CanarySeenFrom $destAbs $canary
} catch {
  Write-Warning "source is not writable, so the aliasing check is weaker than usual"
} finally {
  Remove-Item -Force -LiteralPath (Join-Path $srcAbs $canary) -ErrorAction SilentlyContinue
}
if ($aliased) { Deny-Target }

# Is the source inside the target? Plant the canary in the target and walk up
# from the source. This also confirms the target is writable.
$aliased = $false
try {
  [IO.File]::WriteAllText((Join-Path $destAbs $canary), '')
  $aliased = Test-CanarySeenFrom $srcAbs $canary
} catch {
  Undo-Created; throw "cannot write to target $destAbs"
} finally {
  Remove-Item -Force -LiteralPath (Join-Path $destAbs $canary) -ErrorAction SilentlyContinue
}
if ($aliased) { Deny-Target }

# Every directory we install carries this marker, with this exact first line.
# Uninstall removes only directories that have it, so a skill of your own that
# happens to share a name with one of ours survives.
$marker = '.lean-skills'
$markerLine = 'installed by lean-skills; uninstall removes only directories carrying this file'

# Skills this collection used to ship. They are gone from skills/, so the loops
# below would never look at them, and a stale copy would sit in the target for
# ever - code-review in particular keeps shadowing Claude Code's built-in one.
$retired = @('code-review')

function Test-Ours($dir) {
  $f = Join-Path $dir $marker
  if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { return $false }
  $first = @(Get-Content -LiteralPath $f -TotalCount 1 -ErrorAction SilentlyContinue)
  return ($first.Count -gt 0 -and $first[0] -eq $markerLine)
}

if ($Uninstall) {
  $removed = 0
  $spared = 0
  foreach ($name in (@($srcDirs | ForEach-Object { $_.Name }) + $retired)) {
    $target = Join-Path $destAbs $name
    if (-not (Test-Path -LiteralPath $target)) { continue }
    if ((Test-Ours $target) -or $Adopt) {
      Remove-Item -Recurse -Force -LiteralPath $target
      Write-Host "  removed   $name"
      $removed++
    } else {
      Write-Host "  kept      $name (no ownership marker)"
      $spared++
    }
  }
  Write-Host ""
  Write-Host "$removed removed from $destAbs, $spared kept."
  if ($spared -gt 0) {
    Write-Warning "Those $spared are either yours or were installed before 0.7.0, which did not write markers. Nothing distinguishes the two from here - inspect them, then rerun with -Adopt to remove them anyway."
    exit 3
  }
  exit 0
}

$installed = 0
$kept = 0
$unmarked = 0

foreach ($dir in $srcDirs) {
  $target = Join-Path $destAbs $dir.Name

  # Anything at our name without our marker is either yours or a pre-0.7.0
  # install of ours. We cannot tell, so we do not guess: keep it unless -Adopt.
  $adopting = (Test-Path -LiteralPath $target) -and -not (Test-Ours $target) -and $Adopt
  if ((Test-Path -LiteralPath $target) -and -not (Test-Ours $target) -and -not $Adopt) {
    Write-Host "  kept      $($dir.Name) (no ownership marker)"
    $kept++
    $unmarked++
    continue
  }

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
  if ($adopting) { Write-Host "  adopting  $($dir.Name) (had no marker; replacing its contents)" }
  $staging = Join-Path $destAbs ".lean-skills-staging-$PID"
  if (Test-Path -LiteralPath $staging) { Remove-Item -Recurse -Force -LiteralPath $staging }
  Copy-Item -Recurse -LiteralPath $dir.FullName -Destination $staging
  [IO.File]::WriteAllText((Join-Path $staging $marker), "$markerLine`r`n")
  if (Test-Path -LiteralPath $target) { Remove-Item -Recurse -Force -LiteralPath $target }
  Move-Item -LiteralPath $staging -Destination $target
  Write-Host "  installed $($dir.Name)"
  $installed++
}

# Retire what we no longer ship.
foreach ($name in $retired) {
  $target = Join-Path $destAbs $name
  if (-not (Test-Path -LiteralPath $target)) { continue }
  if ((Test-Ours $target) -or $Adopt) {
    Remove-Item -Recurse -Force -LiteralPath $target
    Write-Host "  retired   $name (no longer part of this collection)"
  } else {
    Write-Host "  kept      $name (retired, no ownership marker)"
    $kept++; $unmarked++
  }
}

Write-Host ""
Write-Host "$installed installed, $kept kept -> $destAbs"
if ($unmarked -gt 0) {
  Write-Warning "$unmarked of those carry no ownership marker. If they are yours, leave them. If you installed lean-skills before 0.7.0 - which did not write markers - this is your upgrade, and it did not happen: rerun with -Adopt."
  exit 3
}
if ($createdLevels.Count -gt 0) {
  Write-Host "First install here - restart your Claude Code session to pick the skills up."
} else {
  Write-Host "Claude Code picks these up in the current session; no restart needed."
}
Write-Host "Remove later with -Uninstall."
Write-Host ""
Write-Host "Resident (model-invoked): verification-before-completion, receiving-code-review,"
Write-Host "                          diagnosing-bugs, spec-review, resolving-merge-conflicts"
Write-Host "Manual (user-invoked):    grill-me, implement, tdd, worktree"
