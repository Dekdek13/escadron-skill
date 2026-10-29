<#
  Escadron Claude v2 : lance des sessions Claude Code, chacune dans SA fenetre,
  connectees au Remote Control, et (optionnel) deja briefees par un fichier de mission.

  Garanties :
  - --model <Model>, sonnet par defaut. Opus autorise depuis le 29/09/2026 quand l'utilisateur le demande
    explicitement (-Model opus) : le hook ne bloque plus que les sous-agents (outil Agent).
    Workers d'un escadron = laisse sonnet, c'est le quota qui paie.
  - --remote-control='<Nom>' (et PAS -n : -n ne fait qu'un nom d'affichage, session invisible sur l'iPhone)
  - refuse un nom deja utilise par une session vivante sur ce PC
  - approuve chaque dossier avant lancement (sinon la session se fige sur "do you trust this folder")
  - brief passe par FICHIER : le prompt initial dit juste de le lire (les apostrophes cassent pwsh -c)
  - avec -Brief (29/09/2026) : mode WORKER autonome. Variables ESCADRON_WORKER=1 et ESCADRON_REPORT posees
    dans la session : guardrails.py y bloque push/merge/deploy/envois, escadron_stop_gate.py l'empeche de
    s'arreter sans rapport. Chaque worker est inscrit dans <dossier du brief>\escadron.json, lu par
    watch-escadron.ps1 (chien de garde). -Resume relance la conversation existante (claude --continue).

  Exemples :
    pwsh -File launch-escadron.ps1 -Names "App-Clips" -Dirs "C:\...\mon-app-wt-clips" -Brief "C:\...\_briefs\clips\BRIEF.md"
    pwsh -File launch-escadron.ps1 -Names "A","B" -Dirs "C:\wtA","C:\wtB" -Brief "C:\...\BRIEF.md"
    pwsh -File launch-escadron.ps1 -Names "Verif-Clips" -Dirs "C:\...\wt-clips" -Chrome
    pwsh -File launch-escadron.ps1 -Names "App-Clips" -Dirs "C:\...\wt-clips" -Brief "C:\...\BRIEF.md" -Resume   (reprise par le chien de garde)
#>
param(
  [Parameter(Mandatory)] [string[]] $Names,
  [Parameter(Mandatory)] [string[]] $Dirs,
  [string] $Brief,
  [string] $Prompt,
  [ValidateSet('sonnet', 'opus', 'fable', 'haiku')] [string] $Model = 'sonnet',
  [ValidateSet('low', 'medium', 'high', 'xhigh', 'max')] [string] $Effort,
  [switch] $Chrome,
  [switch] $Resume,
  [int] $GateMax = 3,
  # 01/10/2026 (marche 2) : journal de decisions exige par le portail de fin (ESCADRON_DECISIONS=1). -NoDecisions pour l'ancien mode.
  [switch] $NoDecisions,
  # Fichier de reglages ajoute a la session (--settings), ex. pour tester des hooks en copie sans toucher ~/.claude.
  [string] $ExtraSettings,
  # 01/10/2026 : chaque session lance ses propres serveurs MCP (mesure du soir : 69 process node MCP = 4 Go, dont
  # 23 chrome-devtools). Un worker -Brief part SANS MCP (--strict-mcp-config) sauf -Mcp full. --chrome (Claude in
  # Chrome) n'est pas concerne.
  [ValidateSet('minimal', 'full')] [string] $Mcp
)
# 01/10/2026 20:42 (bug critique repere par New Identity) : --strict-mcp-config + --mcp-config vers un
# mcpServers vide, combine a --remote-control, tue claude.exe au demarrage (pwsh reste vivant, 0 enfant
# claude.exe apres 20s, reproduit sur 3 workers). 'full' redevient le
# defaut tant que 'minimal' n'est pas prouve stable sur une VRAIE session Remote Control (pas claude -p).
if (-not $Mcp) { $Mcp = 'full' }

# Via "pwsh -File", une liste "A","B" arrive en UNE chaine : on la redecoupe (bug du test du 28/09).
$Names = @($Names | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().Trim('"', "'") } | Where-Object { $_ })
$Dirs  = @($Dirs  | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().Trim('"', "'") } | Where-Object { $_ })

if ($Dirs.Count -ne 1 -and $Dirs.Count -ne $Names.Count) {
  Write-Host "Donne 1 dossier pour tous, ou 1 dossier par nom ($($Names.Count))." -ForegroundColor Red; exit 1
}
if ($Brief -and -not (Test-Path $Brief)) { Write-Host "Brief introuvable : $Brief" -ForegroundColor Red; exit 1 }
if ($Brief -and $Brief -match "'") { Write-Host "Le chemin du brief ne doit pas contenir d'apostrophe." -ForegroundColor Red; exit 1 }

$alive = Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" | Where-Object { $_.CommandLine -match 'remote-control' }
$failed = 0

for ($i = 0; $i -lt $Names.Count; $i++) {
  $name = $Names[$i]
  $dir  = if ($Dirs.Count -eq 1) { $Dirs[0] } else { $Dirs[$i] }

  if ($name -notmatch '^[A-Za-z0-9 ._-]+$') { Write-Host "  [x] $name : nom invalide (pas d'apostrophe ni d'accent)" -ForegroundColor Red; $failed++; continue }
  if (-not (Test-Path $dir)) { Write-Host "  [x] $name : dossier introuvable $dir" -ForegroundColor Red; $failed++; continue }
  if ($alive | Where-Object { $_.CommandLine -match [regex]::Escape("--remote-control='$name'") }) {
    Write-Host "  [x] $name : une session vivante porte deja ce nom, choisis-en un autre" -ForegroundColor Red; $failed++; continue
  }

  # Approbation du dossier, re-verifiee : une session qui demarre reecrit ~/.claude.json avec sa copie en
  # memoire et peut effacer une approbation posee une seconde plus tot (E2E-Mort fige sur « trust », 29/09).
  $trusted = $false
  for ($try = 1; $try -le 5 -and -not $trusted; $try++) {
    node "$PSScriptRoot\check-trust.js" $dir | Out-Null
    if ($LASTEXITCODE -eq 0) { $trusted = $true; break }
    node "$PSScriptRoot\trust-dir.js" $dir | Out-Null
    Start-Sleep -Seconds 2
  }
  if (-not $trusted) { Write-Host "  [x] $name : dossier impossible a approuver : $dir" -ForegroundColor Red; $failed++; continue }

  $flags = "--remote-control='$name' --model $Model"
  if ($Effort) { $flags += " --effort $Effort" }
  if ($Chrome) { $flags += " --chrome" }
  if ($Mcp -eq 'minimal') { $flags += " --strict-mcp-config --mcp-config '$PSScriptRoot\mcp-worker-minimal.json'" }
  if ($ExtraSettings) {
    if (-not (Test-Path $ExtraSettings) -or $ExtraSettings -match "'") { Write-Host "  [x] $name : -ExtraSettings introuvable ou avec apostrophe" -ForegroundColor Red; $failed++; continue }
    $flags += " --settings '$ExtraSettings'"
  }
  $prompt = if ($Prompt) { " '$($Prompt -replace "'", " ")'" } else { "" }
  # Chemin de rapport EXACT dans le prompt : sinon un worker "corrige" son nom (Test-B a ecrit REPORT-TestB.md le 28/09)
  # et wait-reports.sh ne le trouve jamais.
  $envSet = ""
  if ($Brief) {
    $report = Join-Path (Split-Path $Brief -Parent) "REPORT-$name.md"
    # Marche 2 : chaque decision passe par le helper, qui deduit seul le chemin du journal (rien a deviner).
    $journalRule = if ($NoDecisions) { "" } else { " Journal de decisions obligatoire : a chaque decision (garder, jeter, changer d angle, s arreter), lance py $PSScriptRoot\log-decision.py --phase <cadrage|lecture|repro|build|preuve|nettoyage|rapport|blocage> --decision <quoi> --raison <pourquoi> --preuve <commande et resultat ou aucune> --resultat <garde|jete|bloque>. Sans journal, le portail de fin refuse ton arret. Ton lot sera ensuite juge par un verificateur neuf qui rejoue ta condition de fin : seul compte ce qui est commite." }
    $prompt = " 'Tu es $name, worker d un escadron. Lis $Brief (tronc commun + ta section) et execute ton lot jusqu a sa condition de fin. Ton rapport va EXACTEMENT dans $report (ce nom de fichier, sans le modifier). l utilisateur n est pas dans la boucle : ne pose aucune question, ne notifie pas, avance seul. Une decision qui lui revient va dans la section Decisions pour l utilisateur de ton rapport.$journalRule'"
    if ($Resume) {
      # Session NEUVE qui repart de l'etat du disque. Teste le 29/09 : --continue fait quitter aussitot une
      # session Remote Control (aucun transcript local a reprendre).
      $prompt = " 'Tu es $name, worker d un escadron, RELANCE par le chien de garde : la session precedente de ce lot s est arretee en cours de route. Lis $Brief (ta section), puis reconstitue ou elle en etait a partir du disque (git log et git status de ton dossier, fichiers deja crees, rapport partiel eventuel) sans refaire ce qui est fait, et termine le lot jusqu a sa condition de fin. Rapport EXACTEMENT dans $report, avec une ligne qui dit que tu es une reprise. l utilisateur n est pas dans la boucle : ne pose aucune question, avance seul.'"
    }
    # wt.exe separe ses sous-commandes par ';' : on l'echappe en '\;' pour qu'il arrive tel quel a pwsh.
    $envSet = "`$env:ESCADRON_WORKER='1'\; `$env:ESCADRON_REPORT='$report'\; `$env:ESCADRON_GATE_MAX='$GateMax'\; "
    if (-not $NoDecisions) { $envSet += "`$env:ESCADRON_DECISIONS='1'\; " }

    $manifest = Join-Path (Split-Path $Brief -Parent) "escadron.json"
    $list = @()
    if (Test-Path $manifest) { $list = @(Get-Content $manifest -Raw -Encoding UTF8 | ConvertFrom-Json) }
    $prev = $list | Where-Object { $_.name -eq $name } | Select-Object -First 1
    $resumes = if ($Resume -and $prev) { [int]$prev.resumes + 1 } elseif ($prev) { [int]$prev.resumes } else { 0 }
    $list = @($list | Where-Object { $_.name -ne $name }) + [pscustomobject]@{
      name = $name; dir = $dir; report = $report; brief = $Brief; model = $Model; effort = $Effort; gateMax = $GateMax; chrome = [bool]$Chrome
      launched = (Get-Date).ToString('s'); resumes = $resumes
      noDecisions = [bool]$NoDecisions; extraSettings = $ExtraSettings; mcp = $Mcp
    }
    ConvertTo-Json -InputObject @($list) -Depth 3 | Set-Content $manifest -Encoding UTF8
  }

  wt.exe -w new --title "$name" -d "$dir" pwsh -NoExit -c "$envSet`claude $flags$prompt"
  Write-Host "  [+] $name lancee dans $dir" -ForegroundColor Green
  Start-Sleep -Milliseconds 1500
}

Write-Host ""
Write-Host "  $($Names.Count - $failed)/$($Names.Count) sessions lancees ($Model, Remote Control)." -ForegroundColor Cyan
if ($failed) { exit 1 }
