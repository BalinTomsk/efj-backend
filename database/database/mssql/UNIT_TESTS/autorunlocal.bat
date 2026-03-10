rem ----- pass database name as a parameter ----
if exist result.txt del result.txt
if exist error.txt del error.txt
if exist final.txt del final.txt

@echo off
for %%i in (*.sql) do (
@echo  "%%i"
call scriptrunlocal.bat %1 %%i
)

python averify.py 

if exist error.txt del error.txt
