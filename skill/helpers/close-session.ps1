<#
  Ferme proprement une ou plusieurs sessions d'escadron PAR NOM (jamais par date, jamais global).
  Une session = 2 process : le shell pwsh (--remote-control='<Nom>') et son enfant claude.exe.
  Sortie : "FERME <Nom>" si plus aucun process ne survit, "SURVIT <Nom>" sinon (exit 1).

  Exemple (nouvel usage, POSITIONNEL, sans -Names) : pwsh -File close-session.ps1 "App-Clips","App-Paiement"
  Marche aussi sans guillemets sur un nom a espace : pwsh -File close-session.ps1 Anastasia contenu

  CORRECTIF F09 (staging/frictions, pas live) : le bug n'est pas dans le matching
  (Get-CimInstance + [regex]::Escape marchait deja sur un nom a espace, voir preuve
  dans REPORT-DF-Frictions.md). Le bug est au parameter binding PowerShell, AVANT que
  le corps du script s'execute : avec l'ancien appel nomme (-Names Anastasia contenu,
  sans guillemets), PowerShell lie "Anastasia" a -Names puis plante sur "contenu"
  ("A positional parameter cannot be found that accepts argument 'contenu'"). Teste :
  meme avec ValueFromRemainingArguments sur le parametre, PowerShell n'absorbe PAS les
  tokens suivants des lors que le parametre a ete lie PAR NOM -- seul l'appel
  POSITIONNEL (sans taper -Names) laisse ValueFromRemainingArguments recuperer tous les
  tokens restants. Fix : le parametre reste $Names mais l'usage documente passe en
  positionnel ; les fragments coupes par un espace non protege sont alors recaptures
  comme elements supplementaires du tableau (au lieu de faire planter le binding), puis
  rejoints en un seul nom avant de redecouper sur les virgules (usage multi-noms
  documente, qui arrive deja en UNE chaine via "pwsh -File" si quote correctement).
#>
param(
  [Parameter(Mandatory, Position = 0, ValueFromRemainingArguments = $true)]
  [string[]] $Names
)
# Recolle les fragments qu'un espace non protege a coupes en arguments separes
# (ex: appel positionnel Anastasia contenu -> "Anastasia contenu"), puis redecoupe sur
# les virgules pour l'usage multi-noms "A","B" (qui arrive deja en UNE chaine via "pwsh -File").
$raw = ($Names -join ' ')
$Names = @($raw -split ',' | ForEach-Object { $_.Trim().Trim('"', "'") } | Where-Object { $_ })
$bad = 0
foreach ($name in $Names) {
  $sh = Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
        Where-Object { $_.CommandLine -match [regex]::Escape("--remote-control='$name'") }
  if (-not $sh) { Write-Host "ABSENTE $name (aucun process)"; continue }
  # 29/09/2026 : on tue TOUT l'arbre de la session (claude.exe, bash, npm, dev servers next/vite, tsc...),
  # pas seulement pwsh + claude.exe. Avant, un dev server lance par le worker survivait a la fermeture.
  $all = Get-CimInstance Win32_Process
  $ids = @()
  foreach ($s in $sh) {
    $queue = @([int]$s.ProcessId)
    while ($queue.Count) {
      $cur = $queue[0]; $queue = @($queue | Select-Object -Skip 1)
      if ($ids -contains $cur) { continue }
      $ids += $cur
      $queue += @($all | Where-Object { [int]$_.ParentProcessId -eq $cur } | ForEach-Object { [int]$_.ProcessId })
    }
  }
  $ids = $ids | Where-Object { $_ }
  [array]::Reverse($ids)   # feuilles d'abord
  $ports = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $ids -contains [int]$_.OwningProcess } | ForEach-Object LocalPort | Sort-Object -Unique
  if ($ports) { Write-Host "  ports liberes : $($ports -join ', ')" }
  foreach ($id in $ids) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Milliseconds 800
  if (Get-Process -Id $ids -ErrorAction SilentlyContinue) { Write-Host "SURVIT $name ($($ids -join ','))" -ForegroundColor Red; $bad++ }
  else { Write-Host "FERME $name" -ForegroundColor Green }
}
# Les stacks Supabase (docker) ne sont pas dans l'arbre : on les signale.
$stacks = docker ps --format "{{.Names}}" 2>$null | Where-Object { $_ -match '^supabase_db_' } | ForEach-Object { $_ -replace '^supabase_db_','' }
if ($stacks) { Write-Host "  stacks Supabase encore actives : $($stacks -join ', ') (arreter avec : npx supabase stop --workdir <dossier de la stack>)" -ForegroundColor Yellow }
if ($bad) { exit 1 }
