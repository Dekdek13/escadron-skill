<#
  Chien de garde d'un escadron (29/09/2026). l'utilisateur n'est pas dans la boucle : c'est l'orchestrateur
  qui lance ce script EN ARRIERE-PLAN et qui est reveille quand il se termine.

  Lit <dossier mission>\escadron.json (ecrit par launch-escadron.ps1 -Brief) et, toutes les
  -IntervalSeconds, classe chaque worker :
    DONE     rapport present (non vide)
    WORKING  battement de coeur (hooks du worker, .status\<nom>.json) il y a moins de -StaleMinutes
    BUSY     un outil tourne depuis moins de -BusyMinutes
    STALE    arrete sans rapport depuis 1 min, ou rien depuis -StaleMinutes
             -> action 1 : l'orchestrateur envoie un message de relance
    STALE2   toujours rien -StaleMinutes apres la relance -> REPRISE AUTO (close-session + launch -Resume)
    HUNG     un outil tourne depuis plus de -BusyMinutes    -> REPRISE AUTO
    DEAD     plus de process claude                          -> REPRISE AUTO
    BLOCKED  deja -MaxResumes reprises : on ne relance plus, l'orchestrateur le rapporte a la fin
  Le script repare seul DEAD/STALE2/HUNG et continue. Il sort :
    exit 0  ALL_DONE : chaque worker est DONE ou BLOCKED -> l'orchestrateur controle et notifie l'utilisateur UNE fois
    exit 10 ACTION   : un worker est STALE -> l'orchestrateur envoie SendMessage (outil Claude), -MarkNudged,
                       puis relance ce script en arriere-plan. C'est la boucle.

  Usage :
    pwsh -File watch-escadron.ps1 -Mission "C:\...\_briefs\<mission>"            (boucle)
    pwsh -File watch-escadron.ps1 -Mission "C:\...\_briefs\<mission>" -Once      (etat instantane)
    pwsh -File watch-escadron.ps1 -Mission "..." -MarkNudged "App-Clips"           (note une relance envoyee)
#>
param(
  [Parameter(Mandatory)] [string] $Mission,
  [int] $StaleMinutes = 10,
  [int] $BusyMinutes = 30,
  [int] $IntervalSeconds = 120,
  [int] $MaxResumes = 2,
  [switch] $Once,
  [string] $MarkNudged
)

$manifest = Join-Path $Mission "escadron.json"
$stateFile = Join-Path $Mission ".watch-state.json"
if (-not (Test-Path $manifest)) { Write-Host "Pas de manifeste : $manifest"; exit 2 }

function Read-State {
  if (Test-Path $stateFile) { try { return Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable } catch {} }
  return @{}
}
function Write-State($st) { $st | ConvertTo-Json -Depth 3 | Set-Content $stateFile -Encoding UTF8 }

if ($MarkNudged) {
  $st = Read-State
  $st[$MarkNudged] = @{ nudgedAt = (Get-Date).ToString('o') }
  Write-State $st
  Write-Host "relance notee pour $MarkNudged"
  exit 0
}

function Get-Status {
  $workers = @(Get-Content $manifest -Raw -Encoding UTF8 | ConvertFrom-Json)
  $st = Read-State
  $pw = Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" | Where-Object { $_.CommandLine -match 'remote-control' }
  $cl = Get-CimInstance Win32_Process -Filter "Name='claude.exe'"
  foreach ($w in $workers) {
    $now = Get-Date
    $row = [ordered]@{ name = $w.name; state = ''; ageMin = $null; resumes = [int]$w.resumes; detail = '' }
    # 29/09/2026 : un rapport marque provisoire en tete (2 workers l ont fait) ne vaut pas DONE.
    $provisional = $false
    if (Test-Path $w.report) { $head = (Get-Content $w.report -TotalCount 8 -ErrorAction SilentlyContinue) -join " "; $provisional = $head -match '(?i)provisoire|en cours de finalisation|statut.{0,40}en cours|work in progress' }
    if ((Test-Path $w.report) -and (Get-Item $w.report).Length -gt 0 -and -not $provisional) { $row.state = 'DONE'; [pscustomobject]$row; continue }

    $sh = $pw | Where-Object { $_.CommandLine -match [regex]::Escape("--remote-control='$($w.name)'") }
    $alive = $sh -and ($cl | Where-Object { $_.ParentProcessId -in @($sh.ProcessId) })
    if (-not $alive) { $row.state = 'DEAD'; $row.detail = 'aucun process claude'; [pscustomobject]$row; continue }

    # Battement de coeur ecrit par les hooks du worker (escadron_heartbeat.py / escadron_stop_gate.py).
    # Les sessions Remote Control n'ecrivent pas de transcript .jsonl lisible : c'est la seule source fiable.
    $hbFile = Join-Path $Mission ".status\$($w.name).json"
    $hb = if (Test-Path $hbFile) { try { Get-Content $hbFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }
    $launched = [datetime]$w.launched
    $last = if ($hb -and [datetime]$hb.at -gt $launched) { [datetime]$hb.at } else { $launched }
    $age = [math]::Round(($now - $last).TotalMinutes, 1)
    $row.ageMin = $age
    $hbState = if ($hb -and [datetime]$hb.at -gt $launched) { $hb.state } else { 'starting' }
    $row.detail = if ($hb.tool) { "$hbState $($hb.tool)" } else { $hbState }
    $asleep = ($hbState -in 'idle', 'done' -and $age -ge 1) -or ($age -ge $StaleMinutes)
    if ($hbState -eq 'starting') {
      # Aucun signe de vie depuis le lancement. Au-dela de 3 min : session figee au demarrage (dialogue
      # « trust », erreur de lancement). Un message ne la debloquera pas : reprise directe, le lanceur
      # re-approuve le dossier. Jamais STALE : une relance par message serait perdue.
      if ($age -ge 3) { $row.state = 'STALE2'; $row.detail = 'aucun signe de vie au demarrage' } else { $row.state = 'WORKING' }
    } elseif ($hbState -eq 'tool') {
      $row.state = if ($age -lt $BusyMinutes) { 'BUSY' } else { 'HUNG' }
    } elseif (-not $asleep) {
      $row.state = 'WORKING'
    } else {
      $n = $st[$w.name]
      if ($n -and $n.nudgedAt) {
        # Deja relance une fois : on ne relance pas deux fois par message (boucle infinie si le worker
        # repond puis se rendort). S'il a reagi puis s'est rendormi, ou s'il reste muet -StaleMinutes : reprise.
        $nudged = [datetime]$n.nudgedAt
        $since = ($now - $nudged).TotalMinutes
        $row.state = if ($last -gt $nudged -or $since -ge $StaleMinutes) { 'STALE2' } else { 'NUDGED' }
      } else { $row.state = 'STALE' }
    }
    # Deja repris -MaxResumes fois : qu'il soit mort, fige ou rendormi, on arrete (une relance de plus n'aide pas).
    if ($row.state -in 'DEAD', 'STALE', 'STALE2', 'HUNG' -and $row.resumes -ge $MaxResumes) { $row.state = 'BLOCKED'; $row.detail = "$MaxResumes reprises deja faites" }
    [pscustomobject]$row
  }
}

function Invoke-Resume($name) {
  # Reprise automatique : ferme la session par son nom, puis relance une session neuve sur le meme lot.
  $w = @(Get-Content $manifest -Raw -Encoding UTF8 | ConvertFrom-Json) | Where-Object { $_.name -eq $name } | Select-Object -First 1
  $la = @('-NoProfile', '-File', "$PSScriptRoot\launch-escadron.ps1", '-Names', $w.name, '-Dirs', $w.dir, '-Brief', $w.brief,
            '-Model', $w.model, '-Resume')
  if ($w.effort) { $la += @('-Effort', $w.effort) }
  if ($w.gateMax -ne $null) { $la += @('-GateMax', [string]$w.gateMax) }
  if ($w.chrome) { $la += '-Chrome' }
  if ($w.extraSettings) { $la += @('-ExtraSettings', $w.extraSettings) }
  if ($w.noDecisions) { $la += '-NoDecisions' }
  if ($w.mcp) { $la += @('-Mcp', $w.mcp) }
  & pwsh -NoProfile -File "$PSScriptRoot\close-session.ps1" -Names $w.name | Out-Null
  & pwsh @la | Out-Null
  $st = Read-State; $st.Remove($name); Write-State $st
  Write-Host "  reprise automatique : $name (reprise $([int]$w.resumes + 1))"
}

do {
  $rows = @(Get-Status)
  $stamp = (Get-Date).ToString('HH:mm:ss')
  if ($Once) { $rows | Format-Table -AutoSize | Out-String | Write-Host; exit 0 }
  $pending = @($rows | Where-Object { $_.state -notin 'DONE', 'BLOCKED' })
  if ($pending.Count -eq 0) {
    Write-Host "[$stamp] ALL_DONE"; $rows | Format-Table -AutoSize | Out-String | Write-Host; exit 0
  }
  # DEAD / STALE2 / HUNG : le script repare seul (pas besoin de l'orchestrateur).
  $heal = @($rows | Where-Object { $_.state -in 'STALE2', 'HUNG', 'DEAD' })
  foreach ($r in $heal) { Write-Host "[$stamp] $($r.name) $($r.state) ($($r.detail))"; Invoke-Resume $r.name }
  # STALE : seule action qui exige l'orchestrateur (SendMessage est un outil Claude, pas une commande).
  $stale = @($rows | Where-Object { $_.state -eq 'STALE' })
  if ($stale.Count) {
    Write-Host "[$stamp] ACTION"
    $rows | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host "STALE -> SendMessage de relance a chaque nom ci-dessus, puis -MarkNudged <nom>, puis relancer ce script en arriere-plan."
    exit 10
  }
  Start-Sleep -Seconds $IntervalSeconds
} while ($true)
