# Finish the Linux SSD image: read the tail the buffered copy could not
# (unbuffered, exactly the bytes that are left) and append it. Read-only on the disk.
$ErrorActionPreference = 'Stop'
$img = 'G:\linux-backup\linux-ssd-samsung512-disk0.img'
$size = (Get-Disk -Number 0).Size
$have = (Get-Item $img).Length
$need = [int]($size - $have)
"disk $size, image $have, missing $need bytes ($($need / 512) sectors)"
if ($need -le 0) { 'nothing to do'; exit 0 }
$in = New-Object IO.FileStream('\\.\PhysicalDrive0', [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite, 1)
$in.Seek($have, [IO.SeekOrigin]::Begin) | Out-Null
$buf = New-Object byte[] $need
$r = 0
while ($r -lt $need) { $n = $in.Read($buf, $r, $need - $r); if ($n -le 0) { break }; $r += $n }
$in.Close()
"read $r bytes from the disk tail"
$out = New-Object IO.FileStream($img, [IO.FileMode]::Append, [IO.FileAccess]::Write)
$out.Write($buf, 0, $r)
$out.Close()
"image now $((Get-Item $img).Length) bytes" + $(if ((Get-Item $img).Length -eq $size) { ' = the whole disk' } else { ' STILL SHORT' })
