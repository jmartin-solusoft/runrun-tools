# Funciones de apoyo para la API de Runrun (https://runrun.it/api/v1.0/).
# Uso:  . "<SKILL_DIR>\scripts\runrun.ps1"
# Compatible con Windows PowerShell 5.1 y con PowerShell 7. Nunca imprime las claves.

$script:RRBase = 'https://runrun.it/api/v1.0'
$script:RRSecretsDir = Join-Path $env:USERPROFILE '.claude\secrets'
$script:RRHeaders = $null

function Get-RRSecret {
    param([Parameter(Mandatory)][string]$File)
    $path = Join-Path $script:RRSecretsDir $File
    if (-not (Test-Path $path)) {
        throw "Falta $path. El usuario debe ejecutar scripts\guardar-credenciales.ps1 en su propia terminal."
    }
    $secure = Get-Content $path | ConvertTo-SecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Get-RRHeaders {
    if (-not $script:RRHeaders) {
        $script:RRHeaders = @{
            'App-Key'    = (Get-RRSecret 'runrun-api-key.dpapi')
            'User-Token' = (Get-RRSecret 'runrun-user-token.dpapi')
        }
    }
    return $script:RRHeaders
}

# Aplana listas anidadas: la API entrega las listas como un único objeto-lista, y envolverlas con @() no basta.
function ConvertTo-RRPlano {
    param($Valor)
    foreach ($v in @($Valor)) {
        if ($v -is [array]) { ConvertTo-RRPlano $v } else { $v }
    }
}

# Llama a la API. Las listas se devuelven ya aplanadas (elemento a elemento): envuélvelas con @() si necesitas un array.
function Invoke-RR {
    param(
        [string]$Method = 'Get',
        [Parameter(Mandatory)][string]$Path,
        $Body = $null
    )
    $uri = "$($script:RRBase)/$Path"
    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 6
        $r = Invoke-RestMethod -Method $Method -Headers (Get-RRHeaders) -ContentType 'application/json; charset=utf-8' `
            -Body ([Text.Encoding]::UTF8.GetBytes($json)) -Uri $uri
    }
    else {
        $r = Invoke-RestMethod -Method $Method -Headers (Get-RRHeaders) -Uri $uri
    }
    if ($r -is [array]) { ConvertTo-RRPlano $r } else { $r }
}

# Devuelve la fecha (yyyy-MM-dd) de un valor que puede ser DateTime o texto ISO.
function ConvertTo-RRDia {
    param($Valor)
    if ($Valor -is [datetime]) { return $Valor.ToString('yyyy-MM-dd') }
    $s = "$Valor"
    return $s.Substring(0, [Math]::Min(10, $s.Length))
}

function ConvertTo-RRSinTildes {
    param([string]$Texto)
    return ($Texto.Normalize([Text.NormalizationForm]::FormD) -replace '\p{M}', '').ToLowerInvariant().Trim()
}

# Usuario de la clave (id, name...). El id es el que se usa en user_id.
function Get-RRMe { return (Invoke-RR -Path 'users/me') }

# Horas ya imputadas (manual + cronómetro) por día, con el detalle por tarea.
# Ojo: la API solo devuelve las ~1000 últimas entradas de cada tipo, suficiente para las últimas semanas.
function Get-RRHorasDia {
    param([Parameter(Mandatory)][string[]]$Fechas, [string]$UserId)
    if (-not $UserId) { $UserId = (Get-RRMe).id }
    $manual = @(Invoke-RR -Path "manual_work_periods?user_id=$UserId&limit=1000")
    $timer = @(Invoke-RR -Path "work_periods?user_id=$UserId&limit=1000")
    foreach ($f in $Fechas) {
        $m = @($manual | Where-Object { (ConvertTo-RRDia $_.date_to_apply) -eq $f })
        $t = @($timer | Where-Object { (ConvertTo-RRDia $_.start) -eq $f })
        $sm = [double](($m | Measure-Object seconds -Sum).Sum)
        $st = [double](($t | Measure-Object worked_time -Sum).Sum)
        $detalle = @()
        foreach ($e in $m) { $detalle += [pscustomobject]@{ Tipo = 'manual'; EntradaId = $e.id; TareaId = $e.task_id; Horas = [math]::Round($e.seconds / 3600, 2) } }
        foreach ($e in $t) { $detalle += [pscustomobject]@{ Tipo = 'cronometro'; EntradaId = $e.id; TareaId = $e.task_id; Horas = [math]::Round($e.worked_time / 3600, 2) } }
        [pscustomobject]@{
            Fecha      = $f
            Horas      = [math]::Round(($sm + $st) / 3600, 2)
            Manual     = [math]::Round($sm / 3600, 2)
            Cronometro = [math]::Round($st / 3600, 2)
            Detalle    = $detalle
        }
    }
}

# Tareas abiertas del usuario.
function Get-RRTareasAbiertas {
    param([string]$UserId)
    if (-not $UserId) { $UserId = (Get-RRMe).id }
    return @(Invoke-RR -Path "tasks?is_closed=false&user_id=$UserId&limit=200")
}

# Busca tareas (de cualquier usuario) por texto o expresión regular en proyecto, cliente o título.
function Find-RRTarea {
    param([Parameter(Mandatory)][string]$Patron, [int]$Paginas = 6)
    for ($p = 1; $p -le $Paginas; $p++) {
        $r = @(Invoke-RR -Path "tasks?page=$p&limit=200&sort=id&sort_dir=desc")
        if ($r.Count -eq 0) { break }
        $r | Where-Object { "$($_.project_name) $($_.title) $($_.client_name)" -match $Patron } | ForEach-Object { $_ }
    }
}

function Test-RRAsignado {
    param([Parameter(Mandatory)][int]$TareaId, [string]$UserId)
    if (-not $UserId) { $UserId = (Get-RRMe).id }
    $t = Invoke-RR -Path "tasks/$TareaId"
    $ids = @($t.assignments | ForEach-Object { $_.assignee_id })
    return ($ids -contains $UserId)
}

function Set-RRDescripcion {
    param([Parameter(Mandatory)][int]$TareaId, [Parameter(Mandatory)][string]$Texto)
    # La descripción NO se cambia con PUT tasks/N: tiene su propio recurso.
    Invoke-RR -Method Put -Path "tasks/$TareaId/description" -Body @{ description = $Texto } | Out-Null
}

# Crea una tarea copiando proyecto, tipo, equipo y tablero de otra tarea del mismo proyecto.
function New-RRTarea {
    param(
        [Parameter(Mandatory)][string]$Titulo,
        [Parameter(Mandatory)][int]$TareaModelo,
        [string]$Descripcion,
        [string]$UserId
    )
    $me = Get-RRMe
    if (-not $UserId) { $UserId = $me.id }
    $m = Invoke-RR -Path "tasks/$TareaModelo"
    # El equipo del modelo puede ser de otra persona (el usuario "no pertenece al equipo"): se usa uno al que
    # pertenezca el usuario: el del modelo si es suyo; si no, el de su asignación en el modelo; si no, su primer equipo.
    $equipo = $m.team_id
    if ($me.team_ids -notcontains $equipo) {
        $mia = @($m.assignments | Where-Object { $_.assignee_id -eq $UserId }) | Select-Object -First 1
        if ($mia -and $mia.team_id) { $equipo = $mia.team_id } else { $equipo = @($me.team_ids)[0] }
    }
    $body = @{ task = @{
            title          = $Titulo
            project_id     = $m.project_id
            type_id        = $m.type_id
            team_id        = $equipo
            board_id       = $m.board_id          # sin board_id, la etapa "no pertenece al tablero"
            board_stage_id = $m.board_stage_id
            assignments    = @(@{ assignee_id = $UserId; team_id = $equipo })
        } }
    $n = Invoke-RR -Method Post -Path 'tasks' -Body $body
    if ($Descripcion) { Set-RRDescripcion -TareaId $n.id -Texto $Descripcion }
    return $n
}

# Imputa horas manuales (el parte de horas = cronómetro + manual).
function Add-RRHoras {
    param(
        [Parameter(Mandatory)][int]$TareaId,
        [Parameter(Mandatory)][double]$Horas,
        [Parameter(Mandatory)][string]$Fecha,      # yyyy-MM-dd
        [string]$UserId
    )
    if (-not $UserId) { $UserId = (Get-RRMe).id }
    $t = Invoke-RR -Path "tasks/$TareaId"
    # El equipo debe ser el de LA ASIGNACIÓN del usuario en esa tarea; si se manda el equipo de la tarea
    # (puede ser el de otra persona) Runrun responde 404.
    $mia = @($t.assignments | Where-Object { $_.assignee_id -eq $UserId }) | Select-Object -First 1
    $equipo = if ($mia -and $mia.team_id) { $mia.team_id } else { $t.team_id }
    $body = @{ manual_work_period = @{
            task_id        = $TareaId
            user_id        = $UserId
            seconds        = [int][math]::Round($Horas * 3600)
            date_to_apply  = $Fecha
            team_id        = $equipo
            board_stage_id = $t.board_stage_id
            task_state_id  = $t.task_state_id
            task_status_id = $t.task_status_id
        } }
    return (Invoke-RR -Method Post -Path 'manual_work_periods' -Body $body)
}

# Borra una entrada manual (para "mover" horas: primero se crea la nueva y luego se borra la vieja).
function Remove-RRHoras {
    param([Parameter(Mandatory)][int]$EntradaId)
    Invoke-RR -Method Delete -Path "manual_work_periods/$EntradaId" | Out-Null
}

# Horas por día y usuario de una tarea (sirve también para entradas antiguas).
function Get-RRHorasTarea {
    param([Parameter(Mandatory)][int]$TareaId)
    return @(Invoke-RR -Path "tasks/$TareaId/time_worked")
}

# Jornada diaria para una semana (de lunes a viernes).
#  - Viernes: 7 h.
#  - Semana con algún festivo: lunes a jueves 8,5 h (el festivo, 0 h).
#  - Semana sin festivo: lunes a jueves 9 h, salvo el día de la tarde libre, que son 7 h.
function Get-RRJornada {
    param(
        [Parameter(Mandatory)][datetime]$Lunes,
        [string]$TardeLibre = '',                 # lunes, martes, miercoles o jueves
        [datetime[]]$Festivos = @()
    )
    $nombres = @('Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes')
    $festivosDias = @($Festivos | ForEach-Object { $_.Date })
    $hayFestivo = $false
    foreach ($i in 0..4) { if ($festivosDias -contains $Lunes.AddDays($i).Date) { $hayFestivo = $true } }
    $libre = ConvertTo-RRSinTildes $TardeLibre
    foreach ($i in 0..4) {
        $d = $Lunes.AddDays($i).Date
        if ($festivosDias -contains $d) { $h = 0 }
        elseif ($i -eq 4) { $h = 7 }
        elseif ($hayFestivo) { $h = 8.5 }
        elseif ($libre -and ((ConvertTo-RRSinTildes $nombres[$i]) -eq $libre)) { $h = 7 }
        else { $h = 9 }
        [pscustomobject]@{ Fecha = $d.ToString('yyyy-MM-dd'); Dia = $nombres[$i]; Horas = $h }
    }
}
