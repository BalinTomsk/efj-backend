call generate_db_script_ffi2.cmd 

call dbcreator.cmd ffi2.sql 

if exist ffi2.sql del ffi2.sql > nul
echo %date%