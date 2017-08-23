#!/bin/bash
###############################################
# Name:generate_auto_fullbackup.sh
# Author:cdshrewd (cdshrewd#163.com)
# Purpose:Generate snmp oids for ogg to get status info.
# Usage:It should be run by root.You can run it like this:
# './generate_auto_fullbackup.sh -pri_db_name 'oradb' \
#  -pri_backup_dir '/u01/app/backup' -run_backup_now 'yes/no'.
#  If you provide run_backup_now with yes.It will generate a fullbackup
#  script with name $RMAN_AUTO_BACKUP_SCRIPT and runs automatically.
#  This script will create shell file in current direcory.
#  You should make these directories avaliable.
# Modified Date:2017/07/26
###############################################
RUN_BACKUP_NOW=no
COMPRESSED=yes
PRI_BACKUP_DIR=""
PRI_DB_UNIQUE_NAME=""
PRI_ORCL_USER=`ps -ef|grep ora_smon|grep -v grep|head -1|awk '{print $1}'`
RMAN_LOG_PREFIX="auto_fullbackup_cds_"
RMAN_LOG_SUFFIX=".out"
RMAN_AUTO_BACKUP_SCRIPT="auto_create_fullbackup_by_cdshrewd.sh"
if [ $COMPRESSED = "yes" ]; then
COMPRESSED=" AS COMPRESSED BACKUPSET ";
else
COMPRESSED=""
fi

if [ $# -lt 2 ]; then
        echo "You must provide at least 2 params.The params pri_db_name, pri_backup_dir are required. "
        echo "You can use this script likes: \"$0 -pri_db_name 'oradb' \\"
        echo " -pri_backup_dir '/u01/app/backup' \\"
        echo " -run_backup_now 'yes/no' \\"
        exit 1
fi
while [ $# -gt 0 ]
  do
    case $1 in
      -pri_db_name) shift;PRI_DB_UNIQUE_NAME=$1;;         #  primary db_unique_name is set 
      -pri_backup_dir) shift; PRI_BACKUP_DIR=$1; export PRI_BACKUP_DIR;;  # PRI_BACKUP_DIR is set
      -run_backup_now) shift;RUN_BACKUP_NOW=$1;export RUN_BACKUP_NOW;;
    esac;
    shift
  done

if [ -z $PRI_BACKUP_DIR -o -z $PRI_DB_UNIQUE_NAME ]; then
	echo "You must provide at least 2 params.The params pri_db_name, pri_backup_dir are required."
	exit 1
fi

cnt=0
cnt=`cat /proc/cpuinfo|grep processor|wc -l`
a=1
cnt=`expr $cnt / $a`
if [ $cnt -lt 1 ]; then
    cnt=1
fi
	if [ -e "$PRI_BACKUP_DIR/auto_stdcontrol_by_cdshrewd.ctl" ]; then
           mv "$PRI_BACKUP_DIR/auto_stdcontrol_by_cdshrewd.ctl" "$PRI_BACKUP_DIR/auto_stdcontrol_cdshrewd.`date +%y%m%d%H%M%s`.ctl"
        fi
	echo "su - $PRI_ORCL_USER <<EOF" >$RMAN_AUTO_BACKUP_SCRIPT
	echo "export ORACLE_SID=$PRI_DB_UNIQUE_NAME" >>$RMAN_AUTO_BACKUP_SCRIPT
        echo "rman target / <<RMAN">>$RMAN_AUTO_BACKUP_SCRIPT
        echo "run{">>$RMAN_AUTO_BACKUP_SCRIPT
for j  in $(seq $cnt )
        do
                echo "allocate channel ch0$j type disk;">>$RMAN_AUTO_BACKUP_SCRIPT
                if [ $j -eq $cnt ]; then
                        echo "backup $COMPRESSED database format '$PRI_BACKUP_DIR/auto_fulldb_%U_by_cdshrewd.bk' tag='auto_fullbackup_by_cdshrewd';" >>$RMAN_AUTO_BACKUP_SCRIPT
                        echo "backup format='$PRI_BACKUP_DIR/auto_stdcontrol_by_cdshrewd.ctl' as copy current controlfile for standby;" >>$RMAN_AUTO_BACKUP_SCRIPT
                fi
        done

        for (( i=1; i<=$cnt; i++ ))
        do
                echo "release channel ch0$i;">>$RMAN_AUTO_BACKUP_SCRIPT
                if [ $i -eq $cnt ]; then
                        echo "}" >>$RMAN_AUTO_BACKUP_SCRIPT
                        echo "exit" >>$RMAN_AUTO_BACKUP_SCRIPT
                        echo "RMAN" >>$RMAN_AUTO_BACKUP_SCRIPT
                fi
        done
	echo "exit" >>$RMAN_AUTO_BACKUP_SCRIPT
	echo "EOF" >>$RMAN_AUTO_BACKUP_SCRIPT
	chmod a+x  $RMAN_AUTO_BACKUP_SCRIPT
if [ $RUN_BACKUP_NOW = "yes" -a -e $PRI_BACKUP_DIR ]
   then
        logfile_name="${PRI_BACKUP_DIR}/${RMAN_LOG_PREFIX}"`date +%Y%m%dT%H%M%S`"${RMAN_LOG_SUFFIX}"
        nohup ./$RMAN_AUTO_BACKUP_SCRIPT  > $logfile_name 2>&1 &
        echo "$logfile_name"
fi
