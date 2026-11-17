# Guarda las claves de la API de Runrun cifradas con DPAPI (solo las puede descifrar tu usuario de Windows en este equipo).
# LO EJECUTA EL USUARIO EN SU PROPIA TERMINAL. Claude no debe ver ni escribir estas claves.
#
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>\scripts\guardar-credenciales.ps1"
#
# Las pide por teclado (no se muestran) y las guarda en %USERPROFILE%\.claude\secrets\.

$dir = Join-Path $env:USERPROFILE '.claude\secrets'
New-Item -ItemType Directory -Force $dir | Out-Null

$appKey = Read-Host 'App-Key de la API de Runrun' -AsSecureString
$userToken = Read-Host 'User-Token de la API de Runrun' -AsSecureString

$appKey | ConvertFrom-SecureString | Set-Content -Path (Join-Path $dir 'runrun-api-key.dpapi')
$userToken | ConvertFrom-SecureString | Set-Content -Path (Join-Path $dir 'runrun-user-token.dpapi')
Write-Host 'Claves guardadas en' $dir

# Comprobación: pide tu usuario a Runrun y enseña solo el nombre.
. (Join-Path $PSScriptRoot 'runrun.ps1')
try {
    $me = Get-RRMe
    Write-Host "Conectado a Runrun como: $($me.name) (id $($me.id))"
}
catch {
    Write-Host 'No se ha podido validar la clave. Revisa que la App-Key y el User-Token son correctos y vuelve a ejecutar este script.'
}
