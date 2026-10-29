<#
  Vérificateur neuf d'un lot (marche 3 du plan Lauren Tan, 01/10/2026).
  « Celui qui juge n'est jamais celui qui a écrit. » L'orchestrateur ne compte un lot ✅ qu'après ce verdict.

  Ce que fait le script :
  1. lit <mission>\escadron.json pour trouver le dossier et la branche du worker ;
  2. extrait le COMMITÉ de sa branche dans un worktree jetable détaché (le vérificateur ne touche jamais le
     dossier du worker, et ne juge pas des fichiers non commités) ;
  3. lance une session Claude NEUVE en mode headless (claude -p), qui n'a jamais vu le lot : elle lit le brief,
     rejoue elle-même la condition de fin, confronte le code au cahier des charges, et écrit
     <mission>\VERDICT-<Nom>.md dont la 1re ligne est « VERDICT: ACCEPT » ou « VERDICT: REJECT » ;
  4. supprime le worktree jetable.
  Interdits durs actifs pendant la vérification (ESCADRON_WORKER=1 : guardrails.py), et portail de fin :
  la session ne peut pas s'arrêter sans avoir écrit son verdict.

  Exit : 0 ACCEPT · 1 REJECT · 2 pas de verdict lisible · 3 erreur de préparation.

  Exemple :
    pwsh -File verify-lot.ps1 -Mission "C:\...\_briefs\<mission>" -Name "App-Clips"
    pwsh -File verify-lot.ps1 -Mission "..." -Name "App-Clips" -Model opus      (juge d'une autre famille que l'auteur)
#>
param(
  [Parameter(Mandatory)] [string] $Mission,
  [Parameter(Mandatory)] [string] $Name,
  [ValidateSet('sonnet', 'opus')] [string] $Model = 'sonnet',
  [string] $Branch
)
$ErrorActionPreference = 'Stop'
$manifest = Join-Path $Mission 'escadron.json'
if (-not (Test-Path $manifest)) { Write-Host "Pas de manifeste : $manifest"; exit 3 }
$w = @(Get-Content $manifest -Raw -Encoding UTF8 | ConvertFrom-Json) | Where-Object { $_.name -eq $Name } | Select-Object -First 1
if (-not $w) { Write-Host "Worker $Name absent du manifeste"; exit 3 }
$dir = $w.dir
if (-not $Branch) { $Branch = (git -C $dir branch --show-current).Trim() }
$head = (git -C $dir rev-parse $Branch).Trim()
if ($LASTEXITCODE -ne 0 -or -not $head) { Write-Host "Branche introuvable : $Branch"; exit 3 }

$verdict = Join-Path $Mission "VERDICT-$Name.md"
if (Test-Path $verdict) { Move-Item $verdict "$verdict.$(Get-Date -Format yyyyMMdd-HHmmss).old" }
$scratch = Join-Path $Mission ".verify"
New-Item -ItemType Directory -Force $scratch | Out-Null
$wt = Join-Path $scratch "$Name-$($head.Substring(0,8))"
if (Test-Path $wt) { git -C $dir worktree remove --force $wt 2>$null | Out-Null; Remove-Item -Recurse -Force $wt -ErrorAction SilentlyContinue }
git -C $dir worktree add --detach $wt $head 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "worktree jetable impossible"; exit 3 }
Get-ChildItem -Path $dir -Force -File -Filter '.env*' | Where-Object { $_.Name -notmatch 'example' } | Copy-Item -Destination $wt
if ((Test-Path "$wt\package.json") -and (Test-Path "$dir\node_modules")) {
  Push-Location $wt; npm install --silent 2>&1 | Out-Null; Pop-Location
}
node "$PSScriptRoot\check-trust.js" $wt | Out-Null
if ($LASTEXITCODE -ne 0) { node "$PSScriptRoot\trust-dir.js" $wt | Out-Null }

$prompt = @"
Tu es un VERIFICATEUR NEUF. Tu n'as pas ecrit ce lot et tu ne connais pas son auteur. Ton seul travail : dire si le lot du worker $Name remplit sa condition de fin, preuves a l'appui. Personne ne repondra a une question : avance seul.

Terrain :
- Code a juger (commit $head de la branche $Branch, copie jetable) : $wt
- Brief de la mission (lis le tronc commun ET la section de $Name, c'est le cahier des charges) : $($w.brief)
- Rapport de l'auteur : $($w.report) . Ce sont des ALLEGATIONS a verifier, pas des preuves. Ne recopie jamais un resultat du rapport : rejoue-le.

Methode :
1. Ecris d'abord, a partir du brief seul, la liste des points que la condition de fin exige (commandes a lancer, comportements attendus, exemples donnes dans le brief, ce qui ne doit pas changer).
2. Rejoue chaque point toi-meme dans $wt avec la vraie commande, et garde la sortie brute. Pour chaque comportement ou exemple du brief, teste-le directement sur le code (pas seulement via les tests ecrits par l'auteur : des tests verts peuvent avoir ete adaptes a un code faux).
3. Lis le diff du lot (git -C $wt log --oneline -10 ; git -C $wt show --stat HEAD) pour reperer ce qui a ete touche hors perimetre.
4. Ne modifie aucun fichier suivi par git, ne commite rien, ne pousse rien.

Verdict : ecris le fichier $verdict . Sa PREMIERE ligne est exactement « VERDICT: ACCEPT » ou « VERDICT: REJECT » (rien d'autre sur la ligne). ACCEPT seulement si TOUS les points de la condition de fin passent chez toi. Un point non verifiable = REJECT avec la raison. Ensuite : tableau point / verdict (PASS, FAIL, NON VERIFIE) / commande / sortie brute courte, puis « Ecarts avec le rapport de l'auteur », puis « Hors perimetre ». Ta reponse finale tient en une ligne : le verdict.
"@
$promptFile = Join-Path $scratch "prompt-$Name.txt"
Set-Content $promptFile $prompt -Encoding UTF8

$env:ESCADRON_WORKER = '1'
$env:ESCADRON_REPORT = $verdict
$env:ESCADRON_GATE_MAX = '2'
Push-Location $wt
try {
  Get-Content $promptFile -Raw -Encoding UTF8 | claude -p --model $Model --output-format text 2>&1 | Set-Content (Join-Path $scratch "session-$Name.log") -Encoding UTF8
} finally {
  Pop-Location
  Remove-Item Env:ESCADRON_WORKER, Env:ESCADRON_REPORT, Env:ESCADRON_GATE_MAX -ErrorAction SilentlyContinue
  git -C $dir worktree remove --force $wt 2>&1 | Out-Null
}

if (-not (Test-Path $verdict)) { Write-Host "PAS DE VERDICT ($Name) : voir $scratch\session-$Name.log"; exit 2 }
$first = (Get-Content $verdict -TotalCount 1 -Encoding UTF8).Trim()
switch -Regex ($first) {
  '^VERDICT: ACCEPT$' { Write-Host "ACCEPT $Name ($head) -> $verdict"; exit 0 }
  '^VERDICT: REJECT$' { Write-Host "REJECT $Name ($head) -> $verdict"; exit 1 }
  default { Write-Host "VERDICT ILLISIBLE ($Name) : « $first »"; exit 2 }
}
