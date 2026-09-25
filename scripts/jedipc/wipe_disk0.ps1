# Wipe the old Linux SSD (disk 0) and make it E: "fast" - approved by Steve
# 2026-09-25 after the image on G: was verified. Refuses to touch anything
# that does not match exactly what was verified.
$ErrorActionPreference = 'Stop'
$d = Get-Disk -Number 0
$parts = @(Get-Partition -DiskNumber 0 -ErrorAction SilentlyContinue)
"disk 0: $($d.FriendlyName), $($d.Size) bytes, $($d.PartitionStyle), boot=$($d.IsBoot) system=$($d.IsSystem) readonly=$($d.IsReadOnly), $($parts.Count) partition(s), letters: '$(($parts | ForEach-Object { $_.DriveLetter }) -join '')'"
$problems = @()
if ($d.FriendlyName -ne 'SAMSUNG MZFLV512HCJH-000MV') { $problems += 'wrong model' }
if ($d.Size -ne 512110190592) { $problems += 'wrong size' }
if ($d.PartitionStyle -ne 'MBR') { $problems += 'not MBR' }
if ($d.IsBoot -or $d.IsSystem) { $problems += 'boot or system disk' }
if ($parts.Count -ne 1) { $problems += "$($parts.Count) partitions, expected 1" }
if (($parts | Where-Object { $_.DriveLetter -and $_.DriveLetter -ne [char]0 }).Count -gt 0) { $problems += 'has a drive letter' }
if (Get-Volume -DriveLetter E -ErrorAction SilentlyContinue) { $problems += 'E: already in use' }
$img = Get-Item 'G:\linux-backup\linux-ssd-samsung512-disk0.img'
if ($img.Length -ne $d.Size) { $problems += 'backup image is not the full disk' }
if ($problems.Count) { "ABORTED, nothing changed: " + ($problems -join '; '); exit 1 }
'all checks passed: wiping disk 0'
if ($d.IsReadOnly) { Set-Disk -Number 0 -IsReadOnly $false }
Clear-Disk -Number 0 -RemoveData -RemoveOEM -Confirm:$false
Initialize-Disk -Number 0 -PartitionStyle GPT
$p = New-Partition -DiskNumber 0 -UseMaximumSize -DriveLetter E
Format-Volume -DriveLetter E -FileSystem NTFS -NewFileSystemLabel 'fast' -Confirm:$false | Out-Null
$v = Get-Volume -DriveLetter E
"done: E: '$($v.FileSystemLabel)' $($v.FileSystem), $([math]::Round($v.Size/1GB)) GB, $([math]::Round($v.SizeRemaining/1GB)) GB free"
Get-Disk | Sort-Object Number | Format-Table -AutoSize Number, FriendlyName, @{n='GB';e={[math]::Round($_.Size/1GB)}}, PartitionStyle | Out-String
Get-Volume | Where-Object DriveLetter | Sort-Object DriveLetter | Format-Table -AutoSize DriveLetter, FileSystemLabel, FileSystem, @{n='GB';e={[math]::Round($_.Size/1GB)}}, @{n='FreeGB';e={[math]::Round($_.SizeRemaining/1GB)}} | Out-String
