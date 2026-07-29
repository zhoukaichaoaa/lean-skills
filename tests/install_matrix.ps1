<#
.SYNOPSIS
Drive install.ps1 through the same state matrix install_matrix.sh drives install.sh.

.DESCRIPTION
The installer replaces and deletes directories the user owns, so each case runs
the real script out of process and asserts the exit code, the whole tree (type,
content, mode and link target of every entry), and that no staging or outgoing
directory survives.

  tests/install_matrix.ps1                    # this checkout's install.ps1
  tests/install_matrix.ps1 <path\to\ps1>      # e.g. an older tag, for RED
#>
param([string]$Installer)

$ErrorActionPreference = 'Continue'
Set-Location (Join-Path $PSScriptRoot '..')
if (-not $Installer) { $Installer = (Resolve-Path .\install.ps1).Path }
if (-not (Test-Path -LiteralPath $Installer)) { Write-Host "no installer at $Installer"; exit 2 }
$Installer = (Resolve-Path $Installer).Path

$MarkerLine = 'installed by lean-skills; uninstall removes only directories carrying this file'
$W = Join-Path ([IO.Path]::GetTempPath()) ("lsim-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force $W | Out-Null
$Src = Join-Path $W 'src'
New-Item -ItemType Directory -Force $Src | Out-Null
Copy-Item -Recurse .\skills (Join-Path $Src 'skills')
Copy-Item $Installer (Join-Path $Src 'install.ps1')

# Symlinks need Developer Mode or an elevated shell; skip loudly if unavailable.
$Symlinks = $false
try {
  $probe = Join-Path $W 'probe'
  New-Item -ItemType Directory -Force $probe | Out-Null
  New-Item -ItemType SymbolicLink -Path (Join-Path $probe 'l') -Target (Join-Path $probe 'x') -ErrorAction Stop | Out-Null
  $Symlinks = $true
} catch { $Symlinks = $false }

$script:pass = 0; $script:fail = 0
function Report($label, $ok, $detail) {
  if ($ok) { $script:pass++; Write-Host ("  ok    " + $label) }
  else { $script:fail++; Write-Host ("  FAIL  " + $label); if ($detail) { Write-Host ("        " + $detail) } }
}

function Tree($root) {
  if (-not (Test-Path -LiteralPath $root)) { return '' }
  (Get-ChildItem -LiteralPath $root -Recurse -Force | Sort-Object FullName | ForEach-Object {
    $rel = $_.FullName.Substring($root.Length).TrimStart('\')
    if ($_.LinkType -eq 'SymbolicLink' -or $_.LinkType -eq 'Junction') {
      "$rel link $($_.Target)"
    } elseif ($_.PSIsContainer) {
      "$rel dir"
    } else {
      "$rel file " + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
  }) -join "`n"
}

function NoScratch($root) {
  @(Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like '.lean-skills-staging-*' -or $_.Name -like '.lean-skills-outgoing-*' }).Count -eq 0
}

function MakeOccupant($target, $kind, $spare) {
  switch ($kind) {
    'none'   { }
    'dir'    { New-Item -ItemType Directory -Force $target | Out-Null
               [IO.File]::WriteAllText((Join-Path $target 'SKILL.md'), "USERS`n") }
    'ours'   { New-Item -ItemType Directory -Force $target | Out-Null
               [IO.File]::WriteAllText((Join-Path $target 'SKILL.md'), "OLD`n")
               [IO.File]::WriteAllText((Join-Path $target '.lean-skills'), "$MarkerLine`r`n") }
    'file'   { [IO.File]::WriteAllText($target, "USERS FILE`n") }
    'link'   { [IO.File]::WriteAllText($spare, "elsewhere`n")
               New-Item -ItemType SymbolicLink -Path $target -Target $spare | Out-Null }
    'broken' { New-Item -ItemType SymbolicLink -Path $target -Target (Join-Path (Split-Path $target) 'nowhere-at-all') | Out-Null }
  }
}

function RunInstaller($targetDir, [string[]]$argv) {
  $env:CLAUDE_SKILLS_DIR = $targetDir
  $out = Join-Path $W 'out.txt'
  & powershell -NoProfile -File (Join-Path $Src 'install.ps1') @argv > $out 2>&1
  $code = $LASTEXITCODE
  $env:CLAUDE_SKILLS_DIR = $null
  return @{ Code = $code; Out = (Get-Content -Raw $out -ErrorAction SilentlyContinue) }
}

function Case($label, $occupant, [string[]]$argv, $wantRc, $expect) {
  $d = Join-Path $W ("c" + ($script:pass + $script:fail))
  $t = Join-Path $d 'target'
  New-Item -ItemType Directory -Force $t | Out-Null
  $tdd = Join-Path $t 'tdd'
  try { MakeOccupant $tdd $occupant (Join-Path $d 'elsewhere') } catch { Report $label $false "setup: $_"; return }
  $before = Tree $t
  $r = RunInstaller $t $argv
  if ($r.Code -ne $wantRc) { Report $label $false "exit $($r.Code), want $wantRc"; return }
  if (-not (NoScratch $t)) { Report $label $false 'scratch left behind'; return }
  switch ($expect) {
    'keep' {
      $got = (Tree $t) -split "`n" | Where-Object { $_ -like 'tdd*' }
      $want = ($before -split "`n") | Where-Object { $_ -like 'tdd*' }
      if (($got -join '|') -ne ($want -join '|')) { Report $label $false "occupant changed: $($got -join ' / ')"; return } }
    'replace' {
      if (-not (Test-Path -LiteralPath (Join-Path $tdd 'SKILL.md'))) { Report $label $false 'tdd not installed'; return }
      $first = @(Get-Content -LiteralPath (Join-Path $tdd '.lean-skills') -TotalCount 1)
      if ($first.Count -eq 0 -or $first[0] -cne $MarkerLine) { Report $label $false 'marker missing or wrong'; return }
      $srcHash = (Get-FileHash -LiteralPath (Join-Path $Src 'skills\tdd\SKILL.md')).Hash
      $gotHash = (Get-FileHash -LiteralPath (Join-Path $tdd 'SKILL.md')).Hash
      if ($srcHash -ne $gotHash) { Report $label $false 'installed SKILL.md differs from source'; return } }
    'gone' {
      if (Test-Path -LiteralPath $tdd) { Report $label $false 'tdd survived'; return } }
  }
  Report $label $true ''
}

Write-Host "installer under test: $Installer"

Case 'fresh install' 'none' @('-Yes') 0 'replace'

$occupants = @('dir', 'file')
if ($Symlinks) { $occupants += @('link', 'broken') }
foreach ($o in $occupants) {
  Case "occupied by $o, default" $o @('-Yes') 3 'keep'
  Case "occupied by $o, -Adopt"  $o @('-Yes', '-Adopt') 0 'replace'
}

Case 'managed upgrade' 'ours' @('-Yes') 0 'replace'

function UninstallCase($label, $occupant, [string[]]$argv, $wantRc, $expect) {
  $d = Join-Path $W ("u" + ($script:pass + $script:fail))
  $t = Join-Path $d 'target'
  New-Item -ItemType Directory -Force $t | Out-Null
  RunInstaller $t @('-Yes') | Out-Null
  $tdd = Join-Path $t 'tdd'
  if ($occupant -ne 'ours') {
    Remove-Item -Recurse -Force -LiteralPath $tdd -ErrorAction SilentlyContinue
    try { MakeOccupant $tdd $occupant (Join-Path $d 'elsewhere') } catch { Report $label $false "setup: $_"; return }
  }
  $before = (Tree $t) -split "`n" | Where-Object { $_ -like 'tdd*' }
  $r = RunInstaller $t (@('-Uninstall') + $argv)
  if ($r.Code -ne $wantRc) { Report $label $false "exit $($r.Code), want $wantRc"; return }
  if (-not (NoScratch $t)) { Report $label $false 'scratch left behind'; return }
  if ($expect -eq 'keep') {
    $got = (Tree $t) -split "`n" | Where-Object { $_ -like 'tdd*' }
    if (($got -join '|') -ne ($before -join '|')) { Report $label $false 'occupant changed during uninstall'; return }
  } else {
    if (Test-Path -LiteralPath $tdd) { Report $label $false 'tdd survived'; return }
  }
  Report $label $true ''
}

UninstallCase 'uninstall ours'              'ours' @()        0 'gone'
UninstallCase 'uninstall keeps a user dir'  'dir'  @()        3 'keep'
UninstallCase 'uninstall keeps a user file' 'file' @()        3 'keep'
if ($Symlinks) { UninstallCase 'uninstall keeps a broken link' 'broken' @() 3 'keep' }
UninstallCase 'uninstall -Adopt takes a dir' 'dir' @('-Adopt') 0 'gone'

# ---- fault injection: Move-Item fails at one stage of the swap -------------
function InjectCase($label, $occupant, $stage) {
  $d = Join-Path $W ("i" + ($script:pass + $script:fail))
  $t = Join-Path $d 'target'
  New-Item -ItemType Directory -Force $t | Out-Null
  $tdd = Join-Path $t 'tdd'
  try { MakeOccupant $tdd $occupant (Join-Path $d 'elsewhere') } catch { Report $label $false "setup: $_"; return }
  $before = (Tree $t) -split "`n" | Where-Object { $_ -like 'tdd*' }
  $cond = if ($stage -eq 'aside') { '$Destination -like "*lean-skills-outgoing-*"' }
          else { '$LiteralPath -like "*lean-skills-staging-*" -and $Destination -like "*\tdd"' }
  $inject = @"
param([string]`$Target, [string]`$Script)
function Move-Item {
  param([string]`$LiteralPath, [string]`$Destination)
  if ($cond) { throw "injected failure" }
  Microsoft.PowerShell.Management\Move-Item -LiteralPath `$LiteralPath -Destination `$Destination
}
`$env:CLAUDE_SKILLS_DIR = `$Target
. `$Script -Yes -Adopt
"@
  $ip = Join-Path $d 'inject.ps1'
  New-Item -ItemType Directory -Force $d | Out-Null
  [IO.File]::WriteAllText($ip, $inject)
  $out = & powershell -NoProfile -File $ip $t (Join-Path $Src 'install.ps1') 2>&1 | Out-String
  if ($out -notmatch 'injected failure') { Report $label $false 'the injection never fired'; return }
  $got = (Tree $t) -split "`n" | Where-Object { $_ -like 'tdd*' }
  if (($got -join '|') -ne ($before -join '|')) {
    Report $label $false "occupant not restored: $($got -join ' / ')"; return }
  if (-not (NoScratch $t)) { Report $label $false 'scratch left behind'; return }
  Report $label $true ''
}

$injOcc = @('dir', 'file')
if ($Symlinks) { $injOcc += 'broken' }
foreach ($o in $injOcc) {
  InjectCase "swap-in fails over a $o"    $o 'inplace'
  InjectCase "move-aside fails over a $o" $o 'aside'
}

# ---- refusal exit codes: the contract a caller branches on ----------------
function RefusalCase($label, $dir, [string[]]$argv, $wantRc) {
  $env:CLAUDE_SKILLS_DIR = $dir
  $out = Join-Path $W 'ref.txt'
  # From a scratch directory, never the repository: a version that wrongly
  # accepts a relative or drive-relative path creates it in the current one,
  # and the RED run would leave that behind in the checkout.
  $sandbox = Join-Path $W 'sandbox'
  New-Item -ItemType Directory -Force $sandbox | Out-Null
  Push-Location $sandbox
  & powershell -NoProfile -File (Join-Path $Src 'install.ps1') @argv > $out 2>&1
  $code = $LASTEXITCODE
  Pop-Location
  $env:CLAUDE_SKILLS_DIR = $null
  if ($code -ne $wantRc) { Report $label $false "exit $code, want $wantRc"; return }
  Report $label $true ''
}
RefusalCase 'relative target refused'      'rel\path'                     @('-Yes') 2
RefusalCase 'drive-relative target refused' 'C:relative-target'            @('-Yes') 2
RefusalCase 'target is the source refused' (Join-Path $Src 'skills')       @('-Yes') 2
RefusalCase 'unknown option refused'       (Join-Path $W 'ok-target')      @('-Bogus') 2
RefusalCase 'uninstall on a missing target' (Join-Path $W 'never-created') @('-Uninstall') 0

Write-Host ''
if (-not $Symlinks) { Write-Host '  (symlink cases skipped: this shell cannot create links)' }
Write-Host "$script:pass passed, $script:fail failed"
Remove-Item -Recurse -Force $W -ErrorAction SilentlyContinue
if ($script:fail -ne 0) { exit 1 }
