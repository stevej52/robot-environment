# Raw image of PhysicalDrive0 (the Linux SSD) to G:, with a SHA-256 of the bytes
# written and a progress file. Read-only on the source. Run elevated.
$ErrorActionPreference = 'Stop'
$src = '\\.\PhysicalDrive0'
$dst = 'G:\linux-backup\linux-ssd-samsung512-disk0.img'
$log = 'G:\linux-backup\progress.txt'
New-Item -ItemType Directory -Force 'G:\linux-backup' | Out-Null
$size = (Get-Disk -Number 0).Size
$in = New-Object IO.FileStream($src, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite, 4MB, [IO.FileOptions]::SequentialScan)
$out = New-Object IO.FileStream($dst, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::Read, 4MB)
$sha = [Security.Cryptography.SHA256]::Create()
$buf = New-Object byte[] (4MB)
$done = [int64]0; $t0 = Get-Date; $last = $t0
while ($done -lt $size) {
    $want = [int]([math]::Min([int64]$buf.Length, [int64]($size - $done)))
    $n = $in.Read($buf, 0, $want)
    if ($n -le 0) { break }
    $out.Write($buf, 0, $n)
    [void]$sha.TransformBlock($buf, 0, $n, $null, 0)
    $done += $n
    if (((Get-Date) - $last).TotalSeconds -ge 30) {
        $last = Get-Date
        $rate = $done / ((Get-Date) - $t0).TotalSeconds / 1MB
        "{0:u}  {1:N1} GB of {2:N1} GB  {3:N0} MB/s  eta {4:N0} min" -f (Get-Date), ($done / 1GB), ($size / 1GB), $rate, (($size - $done) / 1MB / $rate / 60) | Set-Content $log
    }
}
$sha.TransformFinalBlock($buf, 0, 0) | Out-Null
$out.Flush(); $out.Close(); $in.Close()
$hex = ($sha.Hash | ForEach-Object { $_.ToString('x2') }) -join ''
"$hex  $(Split-Path -Leaf $dst)  $done bytes" | Set-Content "$dst.sha256"
"DONE {0:u}  {1} bytes in {2:N0} min  sha256 {3}" -f (Get-Date), $done, ((Get-Date) - $t0).TotalMinutes, $hex | Set-Content $log
