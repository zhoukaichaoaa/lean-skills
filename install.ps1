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

function Resolve-Physical([string]$Path) {
  # Full path with one level of junction/symlink resolution, so a linked
  # target cannot slip past the source/target guard below.
  $full = [IO.Path]::GetFullPath($Path)
  try {
    $item = Get-Item -LiteralPath $full -ErrorAction Stop
    if ($item.LinkType -and $item.Target) { $full = [IO.Path]::GetFullPath(@($item.Target)[0]) }
  } catch {}
  return $full.TrimEnd('\')
}

$src = Join-Path $PSScriptRoot 'skills'
if (-not (Test-Path -LiteralPath $src)) { throw "skills/ not found next to this script" }
$srcAbs = Resolve-Physical $src

$dest = if ($env:CLAUDE_SKILLS_DIR) { $env:CLAUDE_SKILLS_DIR } else { Join-Path $HOME '.claude\skills' }

$created = $false
if ($Uninstall) {
  if (-not (Test-Path -LiteralPath $dest)) { Write-Host "nothing installed at $dest"; exit 0 }
} elseif (-not (Test-Path -LiteralPath $dest)) {
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  $created = $true
}
$destAbs = Resolve-Physical $dest

# Refuse to operate on the source itself — a CLAUDE_SKILLS_DIR pointing at this
# repo's skills/ would otherwise delete the source before copying it. If we just
# created the target while probing, remove it again so a refused install leaves
# nothing behind (no -Recurse: a non-empty directory is never touched).
if (($destAbs + '\').StartsWith($srcAbs + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
  if ($created) { Remove-Item -LiteralPath $destAbs -Force -ErrorAction SilentlyContinue }
  throw "refusing: target $destAbs is the source (or inside it)"
}

if ($Uninstall) {
  $removed = 0
  foreach ($dir in Get-ChildItem -Directory -LiteralPath $srcAbs) {
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

foreach ($dir in Get-ChildItem -Directory -LiteralPath $srcAbs) {
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
    Remove-Item -Recurse -Force -LiteralPath $target
  }
  Copy-Item -Recurse -LiteralPath $dir.FullName -Destination $target
  Write-Host "  installed $($dir.Name)"
  $installed++
}

Write-Host ""
Write-Host "$installed installed, $kept kept -> $destAbs"
Write-Host "Restart your Claude Code session to pick them up. Remove later with -Uninstall."
Write-Host ""
Write-Host "Resident (model-invoked): verification-before-completion, receiving-code-review,"
Write-Host "                          diagnosing-bugs, code-review"
Write-Host "Manual (user-invoked):    grill-me, implement, tdd, worktree,"
Write-Host "                          resolving-merge-conflicts"
