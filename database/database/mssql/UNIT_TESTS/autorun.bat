@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ------------------------------
REM Save current folder
REM ------------------------------
set "back=%CD%"

echo Reading config.ini

REM ------------------------------
REM Initialize variables
REM ------------------------------
set "server="
set "sqlcmd="
set "engine="
set "pathengine="
set "script="
set "dbmaker="

REM ------------------------------
REM Robust INI parser: supports "key = value", ignores [sections], ; and # comments
REM ------------------------------
for /f "usebackq delims=" %%L in ("config.ini") do (
    set "LINE=%%L"

    REM skip blank lines
    if not "!LINE!"=="" (

        REM skip ; comments
        if not "!LINE:~0,1!"==";" (

            REM skip # comments
            if not "!LINE:~0,1!"=="#" (

                REM skip section headers
                if not "!LINE:~0,1!"=="[" (

                    REM split key=value
                    for /f "tokens=1,* delims==" %%A in ("!LINE!") do (
                        set "K=%%A"
                        set "V=%%B"

                        REM remove UTF-8 BOM if present on first key
                        if "!K:~0,1!"=="﻿" set "K=!K:~1!"

                        REM trim leading spaces from key/value
                        for /f "tokens=* delims= " %%X in ("!K!") do set "K=%%X"
                        for /f "tokens=* delims= " %%Y in ("!V!") do set "V=%%Y"

                        REM remove ALL spaces from key (critical fix for "script = xxx")
                        set "K=!K: =!"

                        if /I "!K!"=="server"     set "server=!V!"
                        if /I "!K!"=="sqlcmd"     set "sqlcmd=!V!"
                        if /I "!K!"=="engine"     set "engine=!V!"
                        if /I "!K!"=="pathengine" set "pathengine=!V!"
                        if /I "!K!"=="script"     set "script=!V!"
                        if /I "!K!"=="dbmaker"    set "dbmaker=!V!"
                    )
                )
            )
        )
    )
)

REM ------------------------------
REM Defaults
REM ------------------------------
if not defined server set "server=localhost"
if not defined sqlcmd set "sqlcmd=SQLCMD.EXE"

REM remove optional surrounding quotes in sqlcmd path
set "sqlcmd=%sqlcmd:"=%"

REM Debug (leave this in until stable)
echo server=[%server%]
echo sqlcmd=[%sqlcmd%]
echo script=[%script%]
echo dbmaker=[%dbmaker%]

REM ------------------------------
REM Cleanup in current folder
REM ------------------------------
if defined script (
  if exist "%script%" del /q "%script%" >nul 2>&1
)
if exist "scriptdb.sql" del /q "scriptdb.sql" >nul 2>&1
if exist "dbname.ini"   del /q "dbname.ini"   >nul 2>&1

cd ..
echo Going upper folder

REM ------------------------------
REM Generate DB script
REM ------------------------------
if not defined dbmaker (
  echo ERROR: config.ini does not define "dbmaker="
  cd /d "%back%"
  exit /b 1
)

call "%dbmaker%"
if errorlevel 1 (
  echo ERROR: %dbmaker% failed
  cd /d "%back%"
  exit /b 1
)

REM ------------------------------
REM Copy generated script back into unit tests folder
REM ------------------------------
if not defined script (
  echo ERROR: config.ini does not define "script="
  cd /d "%back%"
  exit /b 1
)

if exist "%script%" (
  copy /Y "%script%" "%back%\%script%" >nul
) else (
  echo ERROR: expected script "%script%" not found after %dbmaker%
  cd /d "%back%"
  exit /b 1
)

cd /d "%back%"

REM ------------------------------
REM Replace DB name etc
REM ------------------------------
python replacedb.py
if errorlevel 1 (
  echo ERROR: replacedb.py failed
  exit /b 1
)

REM Keep your hardcoded cleanup but quoted
if exist "ffi2.sql" del /q "ffi2.sql" >nul 2>&1

REM ------------------------------
REM Create DB using scriptdb.sql (in parent folder)
REM ------------------------------
cd ..
call "dbcreator.cmd" "%back%\scriptdb.sql"
if errorlevel 1 (
  echo ERROR: dbcreator.cmd failed
  cd /d "%back%"
  exit /b 1
)

if exist "scriptdb.sql" del /q "scriptdb.sql" >nul 2>&1

cd /d "%back%"

REM ------------------------------
REM Cleanup before tests
REM ------------------------------
if defined script (
  if exist "%script%" del /q "%script%" >nul 2>&1
)
if exist "scriptdb.sql" del /q "scriptdb.sql" >nul 2>&1

REM ------------------------------
REM Read dbname.ini
REM ------------------------------
set "dbname="

for /f "usebackq eol=; tokens=1,* delims==" %%A in ("dbname.ini") do (
  set "K=%%A"
  set "V=%%B"
  for /f "tokens=* delims= " %%X in ("!K!") do set "K=%%X"
  for /f "tokens=* delims= " %%Y in ("!V!") do set "V=%%Y"
  if /I "!K!"=="dbname" set "dbname=!V!"
)

if not defined dbname (
  echo ERROR: dbname not found in dbname.ini
  exit /b 1
)

echo DBNAME=%dbname%

REM ------------------------------
REM Run unit tests
REM ------------------------------
call "autorunlocal.bat" "%dbname%"
if errorlevel 1 (
  echo ERROR: autorunlocal.bat failed
  REM continue to drop DB anyway
)

REM ------------------------------
REM Drop database safely
REM ------------------------------
"%sqlcmd%" -S "%server%" -E -Q "IF DB_ID(N'%dbname%') IS NOT NULL BEGIN ALTER DATABASE [%dbname%] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [%dbname%]; END"

REM ------------------------------
REM Final cleanup
REM ------------------------------
if exist "dbname.ini" del /q "dbname.ini" >nul 2>&1
if exist "final.txt"  del /q "final.txt"  >nul 2>&1
if exist "result.txt" del /q "result.txt" >nul 2>&1

endlocal
exit /b 0