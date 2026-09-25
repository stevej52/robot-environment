# Verify the Linux SSD image against the disk itself (read-only on both):
# size, then the first and last MiB and 40 x 16 MiB samples spread over the
# disk, each compared by SHA-256.
$ErrorActionPreference = 'Stop'
$img = 'G:\linux-backup\linux-ssd-samsung512-disk0.img'
$size = (Get-Disk -Number 0).Size
$len = (Get-Item $img).Length
"disk bytes  $size"
"image bytes $len  " + $(if ($len -eq $size) { 'SAME SIZE' } else { 'SIZE MISMATCH' })
$d = New-Object IO.FileStream('\\.\PhysicalDrive0', [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
$f = New-Object IO.FileStream($img, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
$sha = [Security.Cryptography.SHA256]::Create()
$chunk = 16MB
$offsets = @([int64]0, [int64]($size - 1MB))
for ($i = 1; $i -le 40; $i++) { $offsets += [int64]([math]::Floor(($size - $chunk) * $i / 41 / 4096) * 4096) }
$buf = New-Object byte[] $chunk
function Hash-At($stream, [int64]$o, [int]$n) {
    $stream.Seek($o, 'Begin') | Out-Null
    $r = 0; while ($r -lt $n) { $got = $stream.Read($buf, $r, $n - $r); if ($got -le 0) { break }; $r += $got }
    [BitConverter]::ToString($sha.ComputeHash($buf, 0, $r))
}
$bad = 0
foreach ($o in $offsets) {
    $n = [int]([math]::Min([int64]$chunk, [int64]($size - $o)))
    if ((Hash-At $d $o $n) -ne (Hash-At $f $o $n)) { $bad++; "MISMATCH at offset $o" }
}
$d.Close(); $f.Close()
"samples compared: $($offsets.Count), mismatches: $bad"
if (Test-Path "$img.sha256") { Get-Content "$img.sha256" }
