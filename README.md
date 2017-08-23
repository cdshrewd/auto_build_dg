# auto_build_dg
auto build dataguard for Linux single db instance for Oracle 11.2.0.x
Run as root like this:
./auto_build_dg_by_cdshrewd.sh -pri_db_name 'oradb'  \
-std_host_ip '192.168.2.11'  -pri_sys_password 'oracle' \
-pri_backup_dir '/u01/app/backup'  -run_backup_now 'yes' \
-std_backup_dir '/u01/app/backup_tgt' -target_data_dir '/u01/app/oracle/oradata/oradbdg'
There are four scripts.
"auto_build_dg_by_cdshrewd.sh" is the main script.It will called other 3 scripts.
"generate_auto_fullbackup.sh" is used to generate full db backup script.
"generate_auto_restore_db.sh" is used to generate auto restore sxript.
"sshUserSetup.sh" is a script provided by Oracle in oracle grid installation zip file.
It is used to setup SSH connectivity from the host on which it is run to the specified remote hosts.
