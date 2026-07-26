# Install lean-skills into ~/.claude/skills/  (Windows PowerShell)
#
#   .\install.ps1         prompt before overwriting an existing skill
#   .\install.ps1 -Yes    overwrite without prompting
#
# Install elsewhere by setting $env:CLAUDE_SKILLS_DIR first.
[CmdletBinding()]
param([switch]$Yes)

$ErrorActionPreference = 'Stop'

$src = Join-Path $PSScriptRoot 'skills'
$dest = if ($env:CLAUDE_SKILLS_DIR) { $env:CLAUDE_SKILLS_DIR } else { Join-Path $HOME '.claude\skills' }

if (-not (Test-Path -LiteralPath $src)) { throw "skills/ not found next to this script" }
if (-not (Test-Path -LiteralPath $dest)) { New-Item -ItemType Directory -Force -Path $dest | Out-Null }

$installed = 0
$kept = 0

foreach ($dir in Get-ChildItem -Directory -LiteralPath $src) {
  $target = Join-Path $dest $dir.Name
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
Write-Host "$installed installed, $kept kept -> $dest"
Write-Host "Restart your Claude Code session to pick them up."
Write-Host ""
Write-Host "Resident (model-invoked): verification-before-completion, diagnosing-bugs,"
Write-Host "                          tdd, code-review, resolving-merge-conflicts"
Write-Host "Manual (user-invoked):    grill-me, implement, worktree, receiving-code-review"
