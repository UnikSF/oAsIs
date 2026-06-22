# prepare-key.ps1 - efface une cle USB, formate FAT32 label CIDATA, copie les fichiers autoinstall.
# Lance en ADMIN. Refuse d'agir sur autre chose qu'une cle USB (jamais boot/system).
$src = "C:\Users\point\.claude\jobs\b4926696\tmp"
$log = "$src\prepare-key.log"
Start-Transcript -Path $log -Force | Out-Null
try {
  $d = @(Get-Disk | Where-Object { $_.BusType -eq 'USB' -and -not $_.IsBoot -and -not $_.IsSystem })
  if ($d.Count -eq 0) { throw "Aucune cle USB sure detectee." }
  if ($d.Count -gt 1) { throw "Plusieurs cles USB detectees - retire les autres et reessaie." }
  $n = $d[0].Number
  Write-Output ("Cible: Disk {0} - {1} - {2} Go - USB" -f $n, $d[0].FriendlyName, [math]::Round($d[0].Size/1GB,1))

  Write-Output "1) Effacement complet..."
  Clear-Disk -Number $n -RemoveData -RemoveOEM -Confirm:$false
  try { Initialize-Disk -Number $n -PartitionStyle MBR -ErrorAction Stop } catch { }

  Write-Output "2) Partition + formatage FAT32 (label CIDATA)..."
  $p = New-Partition -DiskNumber $n -UseMaximumSize -AssignDriveLetter
  Start-Sleep -Seconds 2
  $v = Format-Volume -Partition $p -FileSystem FAT32 -NewFileSystemLabel CIDATA -Force -Confirm:$false
  $drv = "$($p.DriveLetter):"
  Write-Output ("   -> {0}  label={1}  fs={2}" -f $drv, $v.FileSystemLabel, $v.FileSystem)

  Write-Output "3) Copie user-data + meta-data..."
  Copy-Item "$src\user-data" "$drv\user-data" -Force
  Copy-Item "$src\meta-data" "$drv\meta-data" -Force

  Write-Output "=== Contenu final ==="
  Get-ChildItem "$drv\" -Force | ForEach-Object { Write-Output (" - {0} ({1} o)" -f $_.Name, $_.Length) }
  Write-Output "SUCCES"
} catch {
  Write-Output "ERREUR: $_"
} finally {
  Stop-Transcript | Out-Null
}
