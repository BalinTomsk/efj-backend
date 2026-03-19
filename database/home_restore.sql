use master
go
RESTORE FILELISTONLY 
FROM 
DISK = 'c:\envoinx\fishfind\Apr02-2025Envionx.bak' 

------------------------------------
use master
go
RESTORE DATABASE 
[envionx] 
FROM 
DISK = 'c:\envoinx\fishfind\Apr02-2025Envionx.bak' 
WITH  
MOVE 'DB_111487_fish_data' TO 'c:\DB\envionx.MDF', 
MOVE 'DB_111487_fish_log'  TO 'c:\logs\envionx_Log.ldf'
