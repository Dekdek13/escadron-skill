# Ferme les fenêtres Windows Terminal MORTES (aucune session vivante derrière), garde les vivantes.
# Pourquoi (04/10/2026) : chaque session d'escadron fermée laissait sa fenêtre ouverte (processus terminé
# avec une erreur => Windows Terminal garde la fenêtre). 114 fenêtres mortes s'étaient accumulées.
# Méthode : une console vivante a une PseudoConsoleWindow dont le propriétaire est sa fenêtre Windows Terminal.
# Toute fenêtre CASCADIA_HOSTING_WINDOW_CLASS qui n'est propriétaire d'aucune PseudoConsoleWindow est morte.
# Usage : pwsh -File close-dead-windows.ps1 [-DryRun]
param([switch]$DryRun)
Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices; using System.Collections.Generic;
public class DeadWin { public delegate bool P(IntPtr h, IntPtr l);
[DllImport("user32.dll")] public static extern bool EnumWindows(P p, IntPtr l);
[DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
[DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
[DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
public static List<IntPtr> ByClass(string cls){ var r=new List<IntPtr>(); EnumWindows((h,l)=>{ var c=new StringBuilder(256); GetClassName(h,c,256); if(c.ToString()==cls) r.Add(h); return true;},IntPtr.Zero); return r; }
public static string T(IntPtr h){ var t=new StringBuilder(256); GetWindowText(h,t,256); return t.ToString(); } }
"@
$live = @([DeadWin]::ByClass("PseudoConsoleWindow") | ForEach-Object { [int64][DeadWin]::GetWindow($_, 4) }) | Where-Object { $_ -ne 0 } | Select-Object -Unique
$all = [DeadWin]::ByClass("CASCADIA_HOSTING_WINDOW_CLASS")
$dead = @($all | Where-Object { $live -notcontains [int64]$_ })
Write-Host "Fenêtres terminal : $($all.Count) | vivantes : $($live.Count) | mortes : $($dead.Count)"
foreach ($h in $live) { Write-Host "  GARDE  $([DeadWin]::T([IntPtr]$h))" }
if ($DryRun) { foreach ($h in $dead) { Write-Host "  MORTE  $([DeadWin]::T($h))" }; return }
foreach ($h in $dead) { [DeadWin]::PostMessage($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null; Start-Sleep -Milliseconds 150 }
Start-Sleep 2
Write-Host "Restantes : $(([DeadWin]::ByClass('CASCADIA_HOSTING_WINDOW_CLASS')).Count)"
