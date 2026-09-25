# Sequential read speed of a file, bypassing the Windows file cache
# (FILE_FLAG_NO_BUFFERING), so a just-copied file is really read from disk.
param([string]$Path, [int]$MB = 2048)
$NoBuffering = [IO.FileOptions]0x20000000
$f = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read, 4096, $NoBuffering)
$buf = New-Object byte[] (8MB)
$sw = [Diagnostics.Stopwatch]::StartNew()
$total = [int64]0
while ($total -lt [int64]$MB * 1MB) { $n = $f.Read($buf, 0, $buf.Length); if ($n -le 0) { break }; $total += $n }
$f.Close()
"{0}: {1:N0} MB/s over {2:N0} MB" -f $Path.Substring(0, 2), ($total / 1MB / $sw.Elapsed.TotalSeconds), ($total / 1MB)
