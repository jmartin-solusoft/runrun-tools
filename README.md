# Herramientas de Runrun para Claude Code

## Instalar

```
/plugin marketplace add <URL-o-owner/repo>
/plugin install imputar-runrun@runrun-tools
```

## imputar-runrun

Propone y carga horas en Runrun. Requisitos: Windows, PowerShell y tus propias claves de la API de Runrun.
Las claves son personales y se guardan cifradas (DPAPI) en tu equipo; nunca se suben al repo. Para guardarlas,
ejecuta en tu terminal el script `guardar-credenciales.ps1` de la skill (te lo indica la propia skill la primera vez).

Uso: pide a Claude "propon la imputacion de horas de esta semana" o invoca la skill `imputar-runrun`.
