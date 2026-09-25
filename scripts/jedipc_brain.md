# Rosie's local brain on JEDIPC

The PC upstairs (`JEDIPC`, Windows 10, i9-7920X, 64 GB, **AMD Radeon RX 9060 XT
16 GB**, 192.168.1.137, SSH user `main`, an admin) runs a language model for
the robot: llama.cpp's server with its **Vulkan** build (the card is AMD, so
no CUDA/ROCm), Qwen 2.5 14B Instruct at 4 bit. The robot's `brain` node
(jetnano_bringup) uses it whenever `http://192.168.1.137:8090/health`
answers, and Claude (`ANTHROPIC_API_KEY` on the robot) when it does not.

Everything lives on **G:** (`G:\rosie`); C: has no room (2.5 GB free on
2026-09-25). Set up 2026-09-25 by `scripts/jedipc/`:

| What | Where |
|---|---|
| engine | `G:\rosie\llama\bin\llama-server.exe` (release b11188, `llama-*-bin-win-vulkan-x64.zip`) |
| model | `G:\rosie\models\Qwen2.5-14B-Instruct-Q4_K_M.gguf` (9.0 GB, bartowski on Hugging Face) |
| start script | `G:\rosie\brain.cmd` (port 8090 on all interfaces, `-ngl 99`, context 4096, alias `rosie`) |
| at logon | scheduled task `RosieBrain` (`schtasks /run /tn RosieBrain` to start it now) |
| firewall | inbound TCP 8090 from 192.168.1.0/24, rule "Rosie brain (llama-server 8090)" |
| log | `G:\rosie\logs\brain.log` |

## Redo from scratch

1. `setup1.ps1` (run with `powershell -ExecutionPolicy Bypass -File`): makes
   the folders, fetches the newest llama.cpp release that has a Windows
   Vulkan zip (the "latest" entry on GitHub is a nightly placeholder), unzips
   it, lists the devices. It should print `Vulkan0: AMD Radeon RX 9060 XT`.
2. `download.cmd`: the model, about five minutes at 30 MB/s. Run it in a
   foreground SSH session; as a scheduled task curl sat at 0 bytes.
3. `brain.cmd` to `G:\rosie`, then:

       netsh advfirewall firewall add rule name="Rosie brain (llama-server 8090)" dir=in action=allow protocol=TCP localport=8090 remoteip=192.168.1.0/24
       schtasks /create /f /tn RosieBrain /sc onlogon /tr "cmd /c start /min \"Rosie brain\" G:\rosie\brain.cmd"
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
- Another model: put the .gguf in `G:\rosie\models`, change the `-m` path in
  `brain.cmd`, restart the task. 16 GB of video memory fits a 14B at 4 bit
  with room for context; an 8B at 4 bit (5 GB) is about twice as fast.
