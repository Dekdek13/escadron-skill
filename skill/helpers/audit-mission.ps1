<#
  Audit du matin d'une mission (marche 2 du plan Lauren Tan, 01/10/2026).
  Une session Claude NEUVE (headless, claude -p), qui n'a travaillé sur aucun lot, relit les journaux de
  décisions (decisions-*.tsv), les rapports (REPORT-*.md) et les verdicts des vérificateurs (VERDICT-*.md),
  et écrit <mission>\AUDIT.md qui se termine par la section « ## Attention » : ce qui mérite le regard de
  l'utilisateur. l'utilisateur lit cette section d'abord : il audite des décisions, pas la nuit entière.

  Exit : 0 AUDIT.md écrit avec sa section Attention · 2 sinon.
  Exemple : pwsh -File audit-mission.ps1 -Mission "C:\...\_briefs\<mission>"
#>
param(
  [Parameter(Mandatory)] [string] $Mission,
  [ValidateSet('sonnet', 'opus')] [string] $Model = 'sonnet'
)
$audit = Join-Path $Mission 'AUDIT.md'
if (Test-Path $audit) { Move-Item $audit "$audit.$(Get-Date -Format yyyyMMdd-HHmmss).old" }
$files = @(Get-ChildItem $Mission -File | Where-Object { $_.Name -match '^(decisions-.*\.tsv|REPORT-.*\.md|VERDICT-.*\.md|BRIEF\.md|MISSION\.md)$' -and $_.Name -notmatch 'partial' })
if (-not ($files | Where-Object Name -like 'decisions-*.tsv')) { Write-Host "Aucun decisions-*.tsv dans $Mission"; exit 2 }
$list = ($files | ForEach-Object { "- $($_.FullName)" }) -join "`n"

$prompt = @"
Tu es l'AUDITEUR DU MATIN d'une mission d'escadron. Tu n'as travaille sur aucun lot. l'utilisateur va lire ta section Attention en premier, sur son iPhone : elle doit etre courte, concrete et sourcee. Personne ne repondra a une question.

Fichiers a lire en entier :
$list

Travail :
1. Pour chaque worker, relis son journal de decisions (heure, phase, decision, raison, preuve, resultat) et confronte-le a son rapport et au verdict du verificateur neuf s'il existe.
2. Cherche : une decision sans preuve ou avec une preuve qui n'en est pas une (un build vert pour un comportement, un recit au lieu d'une sortie) ; un rapport qui affirme ce que le journal ne montre pas ; une condition de fin relachee en douce ; un verdict REJECT ; une action hors perimetre ; une decision qui revenait a l'utilisateur prise sans lui ; un trou dans le temps (longue periode sans decision).
3. Verifie toi-meme au moins une affirmation par worker dans les fichiers ou le depot cite (lecture seule, aucune modification, aucun commit).

Ecris $audit avec : un tableau par worker (decisions, preuves solides, preuves faibles, verdict du verificateur), puis les constats sources (fichier + ligne ou heure du journal), puis EN DERNIER la section exactement intitulee « ## Attention » : 3 a 7 puces, la plus grave d'abord, chacune avec sa source et l'action proposee a l'utilisateur. S'il n'y a rien, ecris-le en une puce. Pas d'em-dash. Ta reponse finale : une ligne.
"@
$scratch = Join-Path $Mission '.verify'
New-Item -ItemType Directory -Force $scratch | Out-Null
$promptFile = Join-Path $scratch 'prompt-audit.txt'
Set-Content $promptFile $prompt -Encoding UTF8

$env:ESCADRON_WORKER = '1'
$env:ESCADRON_REPORT = $audit
$env:ESCADRON_GATE_MAX = '2'
Push-Location $Mission
try {
  Get-Content $promptFile -Raw -Encoding UTF8 | claude -p --model $Model --output-format text 2>&1 | Set-Content (Join-Path $scratch 'session-audit.log') -Encoding UTF8
} finally {
  Pop-Location
  Remove-Item Env:ESCADRON_WORKER, Env:ESCADRON_REPORT, Env:ESCADRON_GATE_MAX -ErrorAction SilentlyContinue
}
if ((Test-Path $audit) -and (Select-String -Path $audit -Pattern '^## Attention' -Quiet)) { Write-Host "AUDIT $audit"; exit 0 }
Write-Host "AUDIT ABSENT ou sans section Attention : voir $scratch\session-audit.log"; exit 2
