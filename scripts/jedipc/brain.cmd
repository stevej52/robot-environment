@echo off
rem Rosie's local brain: llama.cpp's server on the Radeon, for the robot on the LAN (port 8090).
rem Started at logon by the scheduled task "RosieBrain"; log in E:\rosie\logs\brain.log.
rem Lives on E: "fast" (the NVMe); G:\rosie is the older copy on the spinning disk.
cd /d E:\rosie
"E:\rosie\llama\bin\llama-server.exe" -m "E:\rosie\models\Qwen2.5-14B-Instruct-Q4_K_M.gguf" --alias rosie --host 0.0.0.0 --port 8090 -ngl 99 -c 4096 -np 1 -t 8 --log-file "E:\rosie\logs\brain.log"
