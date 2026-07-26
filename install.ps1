# Install lean-skills into ~/.claude/skills/
$ErrorActionPreference = 'Stop'

$src = Join-Path $PSScriptRoot 'skills'
$dest = if ($env:CLAUDE_SKILLS_DIR) { $env:CLAUDE_SKILLS_DIR } else { Join-Path $HOME '.claude\skills' }

if (-not (Test-Path $src)) { throw "skills/ not found next to this script" }
if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Force -Path $dest | Out-Null }

foreach ($dir in Get-ChildItem -Directory $src) {
  $target = Join-Path $dest $dir.Name
  if (Test-Path $target) {
    $reply = Read-Host "overwrite existing $($dir.Name)? [y/N]"
    if ($reply -notmatch '^[yY]') { Write-Host "  skipped $($dir.Name)"; continue }
    Remove-Item -Recurse -Force $target
  }
  Copy-Item -Recurse $dir.FullName $target
  Write-Host "  installed $($dir.Name)"
}

Write-Host ""
Write-Host "Installed to $dest - restart your Claude Code session to pick them up."
Write-Host ""
Write-Host "Resident (model-invoked): verification-before-completion, diagnosing-bugs,"
Write-Host "                          tdd, code-review, resolving-merge-conflicts"
Write-Host "Manual (user-invoked):    grill-me, implement, worktree, receiving-code-review"
