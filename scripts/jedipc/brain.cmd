@echo off
rem Rosie's local brain: llama.cpp's server on the Radeon, for the robot on the LAN (port 8090).
rem Started at logon by the scheduled task "RosieBrain"; log in G:\rosie\logs\brain.log.
cd /d G:\rosie
"G:\rosie\llama\bin\llama-server.exe" -m "G:\rosie\models\Qwen2.5-14B-Instruct-Q4_K_M.gguf" --alias rosie --host 0.0.0.0 --port 8090 -ngl 99 -c 4096 -np 1 -t 8 --log-file "G:\rosie\logs\brain.log"
