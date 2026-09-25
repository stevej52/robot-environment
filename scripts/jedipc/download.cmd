@echo off
rem Rosie's local model for JEDIPC: fetched once, resumable, into G:\rosie\models
set MODEL=G:\rosie\models\Qwen2.5-14B-Instruct-Q4_K_M.gguf
set URL=https://huggingface.co/bartowski/Qwen2.5-14B-Instruct-GGUF/resolve/main/Qwen2.5-14B-Instruct-Q4_K_M.gguf
if exist "%MODEL%" exit /b 0
curl.exe -sL -o "%MODEL%.part" "%URL%" && move /y "%MODEL%.part" "%MODEL%"
