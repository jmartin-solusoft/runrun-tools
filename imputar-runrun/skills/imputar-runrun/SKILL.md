---
name: imputar-runrun
description: Propone y carga las horas de la jornada en Runrun (runrun.it) para uno o varios días, repartiéndolas según la actividad real (reuniones, sesiones de Claude Code, issues), con unas reglas de jornada configurables (tarde libre, festivos, viernes de 7 h). Usa esta skill siempre que el usuario pida una propuesta de imputación, cargar o imputar horas, rellenar el parte de horas, mover horas entre tareas o crear una tarea de Runrun para imputar, aunque no diga "Runrun" explícitamente.
---

# Imputar horas en Runrun

Proponer cómo repartir las horas de uno o varios días y, solo cuando el usuario lo apruebe, cargarlas en Runrun mediante su API.

`<SKILL_DIR>` es la carpeta de esta skill (normalmente `C:\Users\<usuario>\.claude\skills\imputar-runrun`). Al ejecutar comandos, sustitúyela por la ruta absoluta real.

## Requisitos y claves

Las claves de la API de Runrun (**App-Key** y **User-Token**) son personales. Se guardan cifradas con DPAPI en `%USERPROFILE%\.claude\secrets\runrun-api-key.dpapi` y `runrun-user-token.dpapi`: solo las descifra el usuario de Windows que las guardó, en ese equipo.

1. Comprueba si existen los dos ficheros.
2. Si faltan, **no pidas las claves por el chat ni las escribas tú**. Dile al usuario que las guarde él, en su propia terminal:

   ```
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>\scripts\guardar-credenciales.ps1"
   ```

   El script las pide por teclado (sin mostrarlas) y comprueba la conexión. Las claves están en la configuración de la API de su cuenta de Runrun.
3. Nunca muestres, copies ni guardes en otro sitio las claves ni las cabeceras.

Solo funciona en Windows (DPAPI) y con PowerShell. Usa la herramienta PowerShell y carga las funciones al principio de cada comando:

```powershell
. "<SKILL_DIR>\scripts\runrun.ps1"
```

Funciones: `Get-RRMe`, `Get-RRHorasDia`, `Get-RRTareasAbiertas`, `Find-RRTarea`, `Test-RRAsignado`, `New-RRTarea`, `Set-RRDescripcion`, `Add-RRHoras`, `Remove-RRHoras`, `Get-RRHorasTarea`, `Get-RRJornada`.

## Reglas de jornada

- **Viernes: 7 h.**
- **Semana con algún festivo:** lunes a jueves 8,5 h (el día festivo, 0 h).
- **Semana sin festivo:** lunes a jueves 9 h, pero cada persona tiene **una tarde libre** a la semana. Ese día son **7 h**. Es frecuente que sea el mismo día todas las semanas (por ejemplo, el martes), pero hay que preguntarlo.

`Get-RRJornada -Lunes <fecha> -TardeLibre <día> -Festivos <fechas>` calcula las horas de cada día de la semana.

## Flujo

### 1. Preguntar lo imprescindible

Antes de proponer nada, pregunta al usuario (lo mínimo; no preguntes lo que ya te ha dicho):

- **Qué días** quiere imputar.
- **Qué día tuvo la tarde libre** esa semana (lunes, martes, miércoles o jueves), o si no la tuvo.
- **Si hubo algún festivo** esa semana, o algún día de vacaciones o ausencia.

Con eso calcula las horas de cada día con `Get-RRJornada`.

### 2. Ver qué hay ya imputado

Con `Get-RRHorasDia -Fechas 'aaaa-mm-dd', …` mira lo que ya hay cargado (manual + cronómetro). El parte de horas es la suma de los dos. Si un día ya tiene horas, propón solo la diferencia y avísalo.

### 3. Reunir indicios de en qué se trabajó

Combina lo que haya disponible:

- **Sesiones de Claude Code**: `scripts\actividad-claude.ps1 -Desde <fecha> -Hasta <fecha> [-Detalle]` cuenta los mensajes del usuario por día y proyecto. Es una aproximación: más mensajes en un proyecto, más tiempo.
- **Agenda de Outlook** (si hay conector de Microsoft 365): reuniones de esos días. Las canceladas no cuentan, y las marcadas como "provisional" se avisan.
- **GitLab** (si hay conector): issues y merge requests tocados.
- **Lo que cuente el usuario.** Si no hay más fuentes, pídele un resumen de cada día.

No inventes precisión: los tiempos son estimaciones y así se le dice.

### 4. Elegir las tareas de Runrun

- **Comprueba siempre el proyecto (y el cliente) al que pertenece cada tarea, antes que fijarte en el título.** Las horas se imputan al proyecto: un título que parece correcto puede estar en el proyecto de otro cliente (por ejemplo, una tarea llamada «Ingesta» puede estar en el proyecto del cliente A y no en el del cliente B, que es donde se trabajó). Lee `project_name` y `client_name` de cada tarea candidata (vienen en `Get-RRTareasAbiertas` y `Find-RRTarea`, o con `Invoke-RR -Path "tasks/<id>"`) y compáralos con el trabajo que se hizo. Si el proyecto no encaja con lo trabajado, descarta la tarea aunque el título coincida y busca otra.
- Parte de las tareas abiertas del usuario (`Get-RRTareasAbiertas`) y de las que ya usó esos días.
- Si no encuentras una tarea adecuada, búscala con `Find-RRTarea -Patron '…'` antes de proponer crear una.
- **Una tarea por issue**, si el usuario trabaja así: título `#N - título de la issue` y la URL de la issue en la descripción. Antes de crear una, comprueba que no existe ya (en ese caso, incluso de otra persona, se usa la existente).
- Si propones crear una tarea nueva, di el proyecto, el título y de qué tarea del mismo proyecto copiarás los campos (`-TareaModelo`).

### 5. Proponer, no imputar

Presenta una tabla por día: **tarea (id y nombre), proyecto, horas y motivo**. Reglas:

- **La columna «Proyecto» es obligatoria**: pon el `project_name` real de cada tarea, leído de Runrun (no deducido del título).
- Cada día suma exactamente su jornada.
- Horas en múltiplos de **0,25**.
- Indica qué tareas son nuevas, qué es incierto y qué supuestos has hecho.
- **Avisa de las tareas en las que el usuario no consta como asignado** (`Test-RRAsignado`). Ahí debe asignarse él. **Tú no lo asignes.**
- **Espera el visto bueno explícito** (un "sí", "imputa", "adelante"). Si pide cambios, rehaz la propuesta. Un "sí" a una propuesta no vale para otra.

### 6. Cargar y comprobar

Cuando el usuario apruebe:

1. Crea las tareas nuevas con `New-RRTarea` (con su descripción).
2. Imputa con `Add-RRHoras -TareaId … -Horas … -Fecha aaaa-mm-dd`.
3. Vuelve a ejecutar `Get-RRHorasDia` y comprueba que **cada día suma su jornada**. Si no cuadra, dilo.
4. Resume lo que has hecho: tareas creadas y horas por tarea y día.

## Mover horas o corregir

- **Mover horas de una tarea a otra:** crea primero la entrada nueva en la tarea de destino con la misma fecha y las mismas horas; después borra la antigua con `Remove-RRHoras`. Comprueba los totales por día antes y después.
- **Para localizar entradas antiguas** usa `Get-RRHorasTarea` (la lista general solo llega a las últimas ~1000 entradas).
- **Borrar una tarea** solo si está a 0 h y después de que el usuario lo confirme, diciendo qué se borra y que no se puede deshacer.
- No edites las imputaciones de otras personas: no se asume que el usuario tenga permiso.

## Trampas de la API (ya resueltas en los scripts)

- La descripción de una tarea se cambia con `PUT tasks/N/description`, no con `PUT tasks/N`.
- Para crear una tarea hay que mandar `board_id` junto con `board_stage_id`, o falla con «La etapa debe pertenecer al tablero».
- Las horas manuales llevan `team_id`, `board_stage_id`, `task_state_id` y `task_status_id` copiados de la tarea.
- `manual_work_periods` y `work_periods` ignoran los filtros por fecha y solo devuelven las ~1000 últimas entradas.
- En PowerShell, escribe `${id}:` y no `$id:` dentro de una cadena, porque `$id:` se interpreta como una variable con ámbito.

## Límites

- No imputes sin aprobación explícita ni inventes horas para llegar al total.
- No muestres ni guardes las claves.
- No asignes al usuario a tareas, no cambies tareas de otras personas ni sus horas.
- No cierres ni borres tareas salvo petición expresa y confirmación.
