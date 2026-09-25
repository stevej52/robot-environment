# Rosie's local brain on JEDIPC, step 1: llama.cpp (Vulkan build) on G:, a
# device check, and the model download started as a background task.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
$root = 'G:\rosie'
New-Item -ItemType Directory -Force "$root\llama", "$root\models", "$root\logs" | Out-Null

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
"admin: $admin"

# the "latest" entry is a nightly placeholder these days: walk recent releases for a real build
$rels = Invoke-RestMethod 'https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=15' -Headers @{ 'User-Agent' = 'rosie' }
$rel = $null; $asset = $null
foreach ($r in $rels) {
    $a = $r.assets | Where-Object { $_.name -like '*win-vulkan-x64.zip' } | Select-Object -First 1
    if ($a) { $rel = $r; $asset = $a; break }
}
if (-not $asset) { "no vulkan asset in the last 15 releases; names: " + (($rels | ForEach-Object { $_.tag_name }) -join ', '); exit 1 }
"release: $($rel.tag_name)  asset: $($asset.name)  $([math]::Round($asset.size/1MB)) MB"
$zip = "$root\llama\$($asset.name)"
if (-not (Test-Path $zip)) { curl.exe -sL -o $zip $asset.browser_download_url }
Expand-Archive -Force $zip "$root\llama\bin"
$exe = Get-ChildItem "$root\llama\bin" -Recurse -Filter llama-server.exe | Select-Object -First 1
"server: $($exe.FullName)"
"--- devices:"
& $exe.FullName --list-devices 2>&1 | Select-Object -First 10

$model = "$root\models\Qwen2.5-14B-Instruct-Q4_K_M.gguf"
$url = 'https://huggingface.co/bartowski/Qwen2.5-14B-Instruct-GGUF/resolve/main/Qwen2.5-14B-Instruct-Q4_K_M.gguf'
@"
@echo off
if exist "$model" exit /b 0
curl.exe -sL -o "$model.part" "$url" && move /y "$model.part" "$model"
"@ | Set-Content -Encoding ASCII "$root\download.cmd"
if (-not (Test-Path $model)) {
    schtasks /create /f /tn RosieModelDownload /sc once /st 23:58 /tr "$root\download.cmd" | Out-Null
    schtasks /run /tn RosieModelDownload | Out-Null
    "model download started in the background (about 9 GB)"
} else { "model already here" }
