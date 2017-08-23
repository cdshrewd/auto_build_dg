#!/bin/bash
###############################################
# Name:generate_auto_restore.sh
# Author:cdshrewd (cdshrewd#163.com)
# Purpose:Generate auto restore scripts for auto build dg.
# Usage:It should be run by root.You can run it like this:
# './generate_auto_restore.sh -pri_db_name 'oradb' \ 
#  -std_db_name 'oradbdg' \ 
#  -data_dir  '/u01/app/oracle/oradata/oradbdg' \
#  -pri_backup_dir '/u01/app/backup'
#  -std_backup_dir '/u01/app/backup_tgt'.
#  If you provide run_restore_now with yes.It will generate a restore
#  script with name auto_restore_db_by_cdshrewd.sh and runs automatically.
#  This script will create shell file in pri_backup_dir direcory.
#  You should make these directories avaliable.
# Modified Date:2017/08/10
###############################################
set -x
PRI_BACKUP_DIR=""
PRI_DB_UNIQUE_NAME=""
PRI_ORCL_USER=`ps -ef|grep ora_smon|grep -v grep|head -1|awk '{print $1}'`
RMAN_LOG_PREFIX="auto_restore_cdshrewd_"
RMAN_LOG_SUFFIX=".out"
PRI_ORCL_USER_HOME=`grep ^$PRI_ORCL_USER /etc/passwd|awk -F ':' '{print $6}'`
if [ $# -lt 5 ]; then
        echo "You must provide 5 params.The params pri_db_name,std_db_name,"
        echo "pri_backup_dir,std_backup_dir and target_data_dir are required. "
        echo "You can use this script likes: \"$0 -pri_db_name 'oradb' \\"
        echo " -std_db_name 'oradbdg' \\"
        echo " -pri_backup_dir '/u01/app/backup' \\"
	echo " -std_backup_dir '/u01/app/backup_tgt' \\"
        echo " -target_data_dir '/u01/app/oracle/oradata/oradbdg'"
        exit 1
fi
while [ $# -gt 0 ]
  do
    case $1 in
      -pri_db_name) shift;PRI_DB_UNIQUE_NAME=$1;;         #  primary db_unique_name is set 
      -std_db_name) shift;STD_DB_UNIQUE_NAME=$1;;         #  standby db_unique_name is set 
      -pri_backup_dir) shift; PRI_BACKUP_DIR=$1; export PRI_BACKUP_DIR;;  # PRI_BACKUP_DIR is set
      -std_backup_dir) shift; STD_BACKUP_DIR=$1; export STD_BACKUP_DIR;;  # STD_BACKUP_DIR is set
      -target_data_dir) shift; TARGET_DATA_DIR=$1;;  # TARGET_DATA_DIR is set
    esac;
    shift
  done

if [ -z $PRI_BACKUP_DIR -o -z $PRI_DB_UNIQUE_NAME -o -z $STD_DB_UNIQUE_NAME ]; then
        echo "You must provide at least 3 params.The params pri_db_name,std_db_name,pri_backup_dir are required. "
	exit 1
fi

DB_FILE_NAME_CONVERT=$PRI_BACKUP_DIR/auto_dbfile_name_convert_by_cdshrewd.out
db_file_name_convert()
{
USERNAME=$PRI_ORCL_USER
TARGET_DIR=$1
su - $USERNAME <<EOF
export ORACLE_SID=$PRI_DB_UNIQUE_NAME
sqlplus -S / as sysdba <<SQL >$DB_FILE_NAME_CONVERT
set heading off feedback off pagesize 0 
select 'set newname for datafile '||df.file_id||' to '''||'${TARGET_DIR}'||'/'||SUBSTR(df.FILE_NAME, INSTR(df.FILE_NAME, '/', -1) + 1)||''';'  from dba_data_files df union
select 'set newname for tempfile '||df.file_id||' to '''||'${TARGET_DIR}'||'/'||SUBSTR(df.FILE_NAME, INSTR(df.FILE_NAME, '/', -1) + 1)||''';'  from dba_temp_files df;
exit
SQL
exit
EOF
}

REDO_FILE_NAME_CONVERT=$PRI_BACKUP_DIR/auto_redo_file_name_convert_by_cdshrewd.out
redo_file_name_convert()
{
USERNAME=$PRI_ORCL_USER
TARGET_DIR=$1
su - $USERNAME <<EOF
export ORACLE_SID=$PRI_DB_UNIQUE_NAME
sqlplus -S / as sysdba <<SQL >$REDO_FILE_NAME_CONVERT
set heading off feedback off pagesize 0 linesize 500
select 'alter database rename file '''||df.member||''' to '''||'${TARGET_DIR}'||'/'||SUBSTR(df.member, INSTR(df.member, '/', -1) + 1)||''';'  from v\\\$logfile df ;
exit
SQL
exit
EOF
}

ONLINE_LOG_DIR=$PRI_BACKUP_DIR/auto_online_logfile_by_cdshrewd.out
ADD_STANDBY_LOG=$PRI_BACKUP_DIR/auto_add_standby_logfile_by_cdshrewd.sh
add_standby_logfiles()
{
USERNAME=$PRI_ORCL_USER
. $PRI_ORCL_USER_HOME/.bash_profile
size_in_mb=50
std_cnt=3
member_cnt=1

su - $USERNAME <<ORAEOF1
. $PRI_ORCL_USER_HOME/.bash_profile
export ORACLE_SID=$PRI_DB_UNIQUE_NAME
sqlplus -S / as sysdba<<SQL >$ONLINE_LOG_DIR
set heading off feedback off pagesize 0 pagesize 200
select distinct SUBSTR(l.member, 0,INSTR(l.member, '/', -1)) from v\\\$logfile l;
exit;
SQL
exit
ORAEOF1

su - $USERNAME <<ORAEOF2
. $PRI_ORCL_USER_HOME/.bash_profile
export ORACLE_SID=$PRI_DB_UNIQUE_NAME
sqlplus -S / as sysdba<<SIZE_IN_MB
set heading off feedback off pagesize 0 verify off echo off serveroutput off termout off
col size_in_mb new_value v_size_in_mb
select max(bytes)/1024/1024 size_in_mb from v\\\$log;
exit v_size_in_mb
SIZE_IN_MB
exit
ORAEOF2
size_in_mb=$?

su - $USERNAME <<ORAEOF3
. $PRI_ORCL_USER_HOME/.bash_profile
export ORACLE_SID=$PRI_DB_UNIQUE_NAME
sqlplus -S / as sysdba<<MAX_CNT
set heading off feedback off pagesize 0 verify off echo off serveroutput off termout off
col max_cnt new_value v_max_cnt
select max(group#)+1 max_cnt from v\\\$log;
exit v_max_cnt
MAX_CNT
exit;
ORAEOF3
std_cnt=$?

su - $USERNAME <<ORAEOF4
. $PRI_ORCL_USER_HOME/.bash_profile
export ORACLE_SID=$PRI_DB_UNIQUE_NAME
sqlplus -S / as sysdba<<MEMBER_CNT
set heading off feedback off pagesize 0 verify off echo off
col m_cnt new_value v_m_cnt
select max(m_cnt) m_cnt from (select count(*) m_cnt,group# from v\\\$logfile group by group#);
exit v_m_cnt
MEMBER_CNT
exit;
ORAEOF4
member_cnt=$?

pnum=0;
for p in `cat $ONLINE_LOG_DIR|grep "/"|head -2`
do
pnum=`expr $pnum + 1`;
if [[ $pnum -eq 1 ]]
 then
PATH_a=$p
else
PATH_b=$p
fi
done
echo "su - $PRI_ORCL_USER <<EOF" >$ADD_STANDBY_LOG
echo "export ORACLE_SID=$STD_DB_UNIQUE_NAME" >>$ADD_STANDBY_LOG
echo "sqlplus / as sysdba" >>$ADD_STANDBY_LOG
echo "alter system set standby_file_management='MANUAL' scope=both;">>$ADD_STANDBY_LOG
cat $REDO_FILE_NAME_CONVERT>>$ADD_STANDBY_LOG
for i in `seq 1 $std_cnt`
do
 grpid=$((i+std_cnt-1))
 add_logfile="alter database add standby logfile group ${grpid} ('"
 for j in `seq 1 $member_cnt`
   do
    if [ -n $TARGET_DATA_DIR ]; then
      if [ $j -eq $member_cnt ]; then
        add_logfile=${add_logfile}${TARGET_DATA_DIR}/stdredo_${grpid}_${j}".log'"
        add_logfile=${add_logfile}") size ${size_in_mb}M;"
      else
        add_logfile=${add_logfile}${TARGET_DATA_DIR}/stdredo_${grpid}_${j}".log',' "
      fi
    else
      if [ $j -eq $member_cnt ]; then
        add_logfile=${add_logfile}${PATH_b}/stdredo_${grpid}_${j}".log'"
        add_logfile=${add_logfile}") size ${size_in_mb}M;"
      else
        add_logfile=${add_logfile}${PATH_a}/stdredo_${grpid}_${j}".log',' "
      fi
     add_logfile=${add_logfile}") size ${size_in_mb}M;"
    fi
   done;
echo $add_logfile>>$ADD_STANDBY_LOG
done;
echo "alter system set standby_file_management='AUTO' scope=both;">>$ADD_STANDBY_LOG
echo "exit;">>$ADD_STANDBY_LOG
echo "exit;">>$ADD_STANDBY_LOG
echo "EOF">>$ADD_STANDBY_LOG
}
add_standby_logfiles

AUTO_RESTORE_SCRIPT=${PRI_BACKUP_DIR}/auto_restore_db_by_cdshrewd.sh
echo $AUTO_RESTORE_SCRIPT
if [ -n $TARGET_DATA_DIR ]; then
db_file_name_convert $TARGET_DATA_DIR
redo_file_name_convert $TARGET_DATA_DIR
else
echo /dev/null>$DB_FILE_NAME_CONVERT
fi
cnt=0
cnt=`cat /proc/cpuinfo|grep processor|wc -l`
a=1
cnt=`expr $cnt / $a`
if [ $cnt -lt 1 ]; then
    cnt=1
fi
	echo "su - $PRI_ORCL_USER <<EOF" >$AUTO_RESTORE_SCRIPT
	echo "export ORACLE_SID=$STD_DB_UNIQUE_NAME" >>$AUTO_RESTORE_SCRIPT
        if [ -n $STD_BACKUP_DIR ]; then
             RMAN_LOG_FILE="$STD_BACKUP_DIR"/"${RMAN_LOG_PREFIX}"`date +%Y%m%dT%H%M`"${RMAN_LOG_SUFFIX}"
        else
        RMAN_LOG_FILE="${RMAN_LOG_PREFIX}"`date +%Y%m%dT%H%M`"${RMAN_LOG_SUFFIX}"
        fi
        echo "rman target / msglog='$RMAN_LOG_FILE' append<<RMAN">>$AUTO_RESTORE_SCRIPT
        echo "crosscheck backup;">>$AUTO_RESTORE_SCRIPT
        echo "delete noprompt expired backupset;">>$AUTO_RESTORE_SCRIPT
        for p in `ls -l $STD_BACKUP_DIR/auto_fulldb_*by_cdshrewd.bk|awk  '{print $NF}'`
        do
        echo "catalog  DEVICE TYPE 'DISK' BACKUPPIECE '$p';" >>$AUTO_RESTORE_SCRIPT
        done
        echo "run{">>$AUTO_RESTORE_SCRIPT
        for j  in $(seq $cnt )
        do
                echo "allocate channel ch0$j type disk;">>$AUTO_RESTORE_SCRIPT
                if [ $j -eq $cnt ]; then
                        cat $DB_FILE_NAME_CONVERT >>$AUTO_RESTORE_SCRIPT
                        echo "restore database;" >>$AUTO_RESTORE_SCRIPT
                        echo "switch datafile all;" >>$AUTO_RESTORE_SCRIPT
                        echo "switch tempfile all;" >>$AUTO_RESTORE_SCRIPT
                fi
        done

        for (( i=1; i<=$cnt; i++ ))
        do
                echo "release channel ch0$i;">>$AUTO_RESTORE_SCRIPT
                if [ $i -eq $cnt ]; then
                        echo "}" >>$AUTO_RESTORE_SCRIPT
                        echo "exit" >>$AUTO_RESTORE_SCRIPT
                        echo "RMAN" >>$AUTO_RESTORE_SCRIPT
                fi
        done
echo "exit" >>$AUTO_RESTORE_SCRIPT
echo "EOF" >>$AUTO_RESTORE_SCRIPT
