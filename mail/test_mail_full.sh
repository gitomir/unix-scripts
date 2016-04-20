#!/bin/bash
start_time="2014-04-29 15:38:26"

data="2014-04-29__15:39:34"

backupdir="/sofia-nas/mysqldumps/"
databasename="axsmarine_common"
tablename="axs_files_attach"
MYSQLCOMMAND="mysql"
mysqluser="user1"
mysqlpass="crim73"
devserver="192.168.9.101"
testdb="TestProdDatabaseBackups"
end_time="2014-04-29 19:43:54"

timestamp="29Apr2014"
#timestamp=`date '+%d%b%Y'`



body="START TIME: $start_time \r\nEND TIME: $end_time \r\n"
body1=$body`tail -n 2 /root/cronjobs/prod_mysql_backup_logs/mysql_backup_log_2014-04-13__19:00:01.log`
body2=`$MYSQLCOMMAND -u $mysqluser -p$mysqlpass -h $devserver -e 'SELECT COUNT(*) as count FROM axs_files_attach\G;' $testdb | grep "count" | awk -F": " {' print $2 '}`
body3="\r\nSuccessfully tested $databasename.gz archive created from Colt: \r\n- Total records imported into test table $tablename : $body2"
body4="$body1\n$body3"

echo -e $body4 | mail -s "production MySQL Daily Backup" boyan.milanov@axsmarine.com
