# Rosie's local brain on JEDIPC

The PC upstairs (`JEDIPC`, Windows 10, i9-7920X, 64 GB, **AMD Radeon RX 9060 XT
16 GB**, 192.168.1.137, SSH user `main`, an admin) runs a language model for
the robot: llama.cpp's server with its **Vulkan** build (the card is AMD, so
no CUDA/ROCm), Qwen 2.5 14B Instruct at 4 bit. The robot's `brain` node
(jetnano_bringup) uses it whenever `http://192.168.1.137:8090/health`
answers, and Claude (`ANTHROPIC_API_KEY` on the robot) when it does not.

Everything lives on **E: "fast"**, the 512 GB Samsung NVMe that held Linux
until 2026-09-25. That drive was imaged first to
`G:\linux-backup\linux-ssd-samsung512-disk0.img` (full size, 42 sampled
checksums against the disk all matching), then wiped with Steve's go by
`wipe_disk0.ps1`, which refuses to run unless disk 0 is exactly that drive.
E: reads the model at 1,396 MB/s against G:'s 74 MB/s: a cold start to ready
is about 22 s instead of about two minutes. `G:\rosie` is the first copy,
kept as a spare. C: has no room (2.5 GB free on 2026-09-25).

| What | Where |
|---|---|
| engine | `E:\rosie\llama\bin\llama-server.exe` (release b11188, `llama-*-bin-win-vulkan-x64.zip`) |
| model | `E:\rosie\models\Qwen2.5-14B-Instruct-Q4_K_M.gguf` (9.0 GB, bartowski on Hugging Face) |
| start script | `E:\rosie\brain.cmd` (port 8090 on all interfaces, `-ngl 99`, context 4096, alias `rosie`) |
| at logon | scheduled task `RosieBrain` (`schtasks /run /tn RosieBrain` to start it now) |
| firewall | inbound TCP 8090 from 192.168.1.0/24, rule "Rosie brain (llama-server 8090)" |
| log | `E:\rosie\logs\brain.log` |

Measured from the robot: first words 0.4 to 0.8 s with the persona cached,
32 tokens a second, two sentences in about a second.

## Redo from scratch

1. `setup1.ps1` (run with `powershell -ExecutionPolicy Bypass -File`): makes
   the folders, fetches the newest llama.cpp release that has a Windows
   Vulkan zip (the "latest" entry on GitHub is a nightly placeholder), unzips
   it, lists the devices. It should print `Vulkan0: AMD Radeon RX 9060 XT`.
   It writes to G:; move to E: with `robocopy G:\rosie E:\rosie /E /J`.
2. `download.cmd`: the model, about five minutes at 30 MB/s. Run it in a
   foreground SSH session; as a scheduled task curl sat at 0 bytes.
3. `brain.cmd` to `E:\rosie`, then:

       netsh advfirewall firewall add rule name="Rosie brain (llama-server 8090)" dir=in action=allow protocol=TCP localport=8090 remoteip=192.168.1.0/24
       schtasks /create /f /tn RosieBrain /sc onlogon /tr "cmd /c start /min \"Rosie brain\" E:\rosie\brain.cmd"
       schtasks /run /tn RosieBrain

4. Check: `curl http://192.168.1.137:8090/health` from the robot, and the
   brain node's log says `local model at ...: up`.

## Notes

- PowerShell 5.1 with `$ErrorActionPreference = 'Stop'` turns a native
  program's stderr into a fatal error: run `llama-server.exe` from cmd, not
  from a strict script.
- The task runs in `main`'s interactive session (the PC is normally logged
  in), so the GPU is available to it; a SYSTEM service in session 0 may not
  get Vulkan.
- Another model: put the .gguf in `E:\rosie\models`, change the `-m` path in
  `brain.cmd`, restart the task. 16 GB of video memory fits a 14B at 4 bit
  with room for context; an 8B at 4 bit (5 GB) is about twice as fast.
- `readspeed.ps1 -Path <file>` measures a drive's real read speed with the
  file cache bypassed.
- `image_disk0.ps1` stopped 2.3 MB before the end: a buffered FileStream on a
  raw disk tries to fill its whole buffer on the last short read and runs off
  the end ("The drive cannot find the sector requested"). `image_tail.ps1`
  reads the rest unbuffered. Use buffer size 1, or exact multiples, on raw disks.
- The Linux image: that filesystem was not cleanly unmounted, so 7-Zip 18
  shows a headers warning. To get files out, attach it on a Linux machine
  (H2-Host): `sudo losetup -Pf --show <img>` then mount the first partition
  read-only.
