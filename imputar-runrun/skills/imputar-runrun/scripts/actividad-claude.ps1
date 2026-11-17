# Cuenta, por día y por proyecto, los mensajes que el usuario ha escrito en sus sesiones de Claude Code.
# Sirve como indicio de en qué se ha trabajado cada día (más mensajes en un proyecto = más tiempo, aproximadamente).
# Solo lee los historiales locales (%USERPROFILE%\.claude\projects). No cambia nada.
#
#   powershell.exe -NoProfile -File "<SKILL_DIR>\scripts\actividad-claude.ps1" -Desde 2026-11-09 -Hasta 2026-11-10
#   Con -Detalle muestra también el comienzo de cada mensaje.

param(
    [Parameter(Mandatory)][datetime]$Desde,
    [datetime]$Hasta = (Get-Date),
    [switch]$Detalle
)

$desde = $Desde.Date
$hasta = $Hasta.Date.AddDays(1)
$raiz = Join-Path $env:USERPROFILE '.claude\projects'
$archivos = Get-ChildItem $raiz -Recurse -Filter *.jsonl -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $desde -and $_.FullName -notmatch '\\subagents\\' }

$vistos = @{}
$filas = New-Object System.Collections.Generic.List[object]
foreach ($f in $archivos) {
    $proyecto = $f.Directory.Name -replace '^[A-Za-z]--', ''
    foreach ($linea in [IO.File]::ReadLines($f.FullName)) {
        if ($linea.Length -lt 20 -or $linea -notmatch '"type":"user"') { continue }
        try { $o = $linea | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        if ($o.type -ne 'user' -or $o.isMeta -or $o.isSidechain) { continue }
        $ts = ([datetime]$o.timestamp).ToLocalTime()
        if ($ts -lt $desde -or $ts -ge $hasta) { continue }
        $c = $o.message.content
        if ($c -is [string]) { $txt = $c }
        else { $txt = (($c | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join "`n") }
        $txt = $txt.Trim()
        if (-not $txt) { continue }
        # Fuera avisos del sistema, resúmenes automáticos y notificaciones.
        if ($txt -match '^(<system-reminder|<task-notification|<command-|<local-command|Caveat:|\[Request interrupted|<ci-monitor|<side-sessions|This session is being continued|<artifact|<scheduled)') { continue }
        $txt = (($txt -replace '(?s)<system-reminder>.*?</system-reminder>', '').Trim()) -replace '\s+', ' '
        if (-not $txt) { continue }
        $clave = "$($f.Name)|$($txt.ToLowerInvariant())"   # evita contar dos veces las sesiones bifurcadas
        if ($vistos.ContainsKey($clave)) { continue }
        $vistos[$clave] = 1
        $filas.Add([pscustomobject]@{ Ts = $ts; Dia = $ts.ToString('yyyy-MM-dd'); Proyecto = $proyecto; Texto = $txt })
    }
}

Write-Host "Mensajes por día y proyecto ($($filas.Count) en total):"
$filas | Group-Object Dia, Proyecto | Sort-Object Name | ForEach-Object {
    $orden = $_.Group | Sort-Object Ts
    '{0,4} | {1} | {2}-{3}' -f $_.Count, $_.Name, $orden[0].Ts.ToString('HH:mm'), $orden[-1].Ts.ToString('HH:mm')
}
if ($Detalle) {
    Write-Host ''
    $filas | Sort-Object Ts | ForEach-Object {
        $t = $_.Texto
        if ($t.Length -gt 120) { $t = $t.Substring(0, 120) + '…' }
        '{0:yyyy-MM-dd HH:mm} ({1}) {2}' -f $_.Ts, $_.Proyecto, $t
    }
}
