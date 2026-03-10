@echo  %2 >> result.txt

for /f "tokens=1,2 delims==" %%a in (config.ini) do (
if %%a==server     set server=%%b
if %%a==sqlcmd     set sqlcmd=%%b
) 

call %sqlcmd% -S %server% -E -d %1 -i %2 >> result.txt
