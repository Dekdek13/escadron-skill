<#
  Cree un worktree git isole pour UN worker d'escadron, pret a l'emploi.
  - dossier : <parent du repo>\<nom du repo>-wt-<Lot>   · branche : wt/<Lot>
  - copie les fichiers d'env non versionnes (.env, .env.local, ...) sauf les *.example
  - npm install si package.json (sauf -NoInstall)
  - approuve le dossier ("do you trust this folder") pour que la session ne se fige pas
  Sortie : derniere ligne = "WORKTREE <chemin>" (a reutiliser dans launch-escadron.ps1 -Dirs)

  Exemple :
    pwsh -File new-worktree.ps1 -Repo "C:\Users\<toi>\Projets\mon-app" -Lot feature-map
#>
param(
  [Parameter(Mandatory)] [string] $Repo,
  [Parameter(Mandatory)] [string] $Lot,
  [string] $Base,
  [switch] $NoInstall
)
$ErrorActionPreference = "Stop"
if (-not (Test-Path "$Repo\.git")) { Write-Host "Pas un repo git : $Repo" -ForegroundColor Red; exit 1 }
if ($Lot -notmatch '^[A-Za-z0-9._-]+$') { Write-Host "Lot invalide (lettres, chiffres, . _ - seulement) : $Lot" -ForegroundColor Red; exit 1 }

$repoName = Split-Path $Repo -Leaf
$wt = Join-Path (Split-Path $Repo -Parent) "$repoName-wt-$Lot"
$branch = "wt/$Lot"
if (Test-Path $wt) { Write-Host "Existe deja : $wt (reprends-le ou supprime-le d'abord)" -ForegroundColor Red; exit 1 }
if (-not $Base) { $Base = (git -C $Repo branch --show-current).Trim() }

# Un worktree ne contient QUE le commite : prevenir si le repo a du non-commite
$dirty = git -C $Repo status --porcelain
if ($dirty) { Write-Host "  ATTENTION : $repoName a des changements non commites, ils ne seront PAS dans le worktree." -ForegroundColor Yellow }

git -C $Repo worktree add -b $branch $wt $Base | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "git worktree add a echoue" -ForegroundColor Red; exit 1 }

# Fichiers d'env non versionnes (piege : sans eux l'app ne demarre pas)
Get-ChildItem -Path $Repo -Force -File -Filter ".env*" |
  Where-Object { $_.Name -notmatch 'example' } |
  ForEach-Object { Copy-Item $_.FullName (Join-Path $wt $_.Name); Write-Host "  env copie : $($_.Name)" }

if ((Test-Path "$wt\package.json") -and -not $NoInstall) {
  Write-Host "  npm install..."
  Push-Location $wt; npm install --silent 2>&1 | Out-Null; $rc = $LASTEXITCODE; Pop-Location
  if ($rc -ne 0) { Write-Host "  npm install a echoue (rc=$rc)" -ForegroundColor Red; exit 1 }
}

node "$PSScriptRoot\check-trust.js" $wt | Out-Null
if ($LASTEXITCODE -ne 0) { node "$PSScriptRoot\trust-dir.js" $wt | Out-Null }

Write-Host "  branche : $branch (depuis $Base)"
Write-Host "WORKTREE $wt"
