#!/bin/bash

# this is a parallel mysqldump lbzip2 script for hourly backups
# files must be in format <DB_NAME>.`date '+%d%b%Y'`.bz2
dump_timestamp=`date '+%d%b%Y-%Hh'`

mysql_slave='aws-db-2'
mysql_user='user1'
mysql_password='crim73'
cpu_cores="7" # cpus of host running this proccess

backup_dir="/backup/mysqldumps/"

#dump_dir makes a directory with the current date/time
dump_dir=$backup_dir$dump_timestamp

#we create the dir because we can not create directorys in S3
mkdir $dump_dir

log_file="/backup/log/backup_v3.$dump_timestamp.log"

zabbix_host="10.10.0.40"
zabbix_port="10051"
zabbix_item_count="BKP[dumps,count]"
zabbix_item_size="BKP[dumps,size]"

zabbix_sender="/usr/bin/zabbix_sender -z $zabbix_host -p $zabbix_port -s AWS-BACKUP "

#timestamp function
timestamp() {
        date +"%T"
}

# Tell zabbix server that script is running (key is boolean)
z_out_start=`$zabbix_sender -k BKP[proc,started] -o 1`

msg_start="$(timestamp) Starting $0 vars: \n\t SLAVE:[$mysql_slave]\n\t DIR:[$backup_dir]\n\t CPU:[$cpu_cores]\n\t LOG:[$log_file]\n"
#start log to file
echo -e $msg_start >> $log_file
echo -e "$(timestamp) Z[START]: 1" >> $log_file
#log to stdout

/usr/bin/mysql -h $mysql_slave -u$mysql_user -p$mysql_password -e 'show databases' -s --skip-column-names \
        | /bin/egrep -iv "^(test|TEST|performance_schema|information_schema)\$" \
        | /usr/bin/parallel --gnu -j$cpu_cores "/usr/bin/mysqldump -u$mysql_user -p$mysql_password -h $mysql_slave --routines --triggers --events --skip-comments --single-transaction {} | /usr/bin/lbzip2 > $dump_dir/{}.$dump_timestamp.bz2"

cd $dump_dir
cnt_files=`ls -al *$dump_timestamp*.bz2 | wc -l`
size_files=`du -bsc *$dump_timestamp*.bz2 | grep total | awk -F' ' '{print $1}'`

# Tell zabbix the current variables and that script goes into upload state
z_out_c=`$zabbix_sender -k BKP[dumps,count] -o $cnt_files`
z_out_s=`$zabbix_sender -k BKP[dumps,size] -o $size_files`
z_out_end=`$zabbix_sender -k BKP[proc,started] -o 2`

# Upload to S3 WARNING THE END / on the destination is mandatory !!!
echo -e "$(timestamp) Starting S3 UPLOAD:" >> $log_file
/usr/local/bin/s3cmd put --config /root/.s3cfg --recursive $dump_dir/* s3://backup-mysqldumps/$dump_timestamp/ >> /backup/log/s3cmd_temp_log_$dump_timestamp
echo -e "$(timestamp) Finished the S3 upload." >> $log_file

cnt_files_s3=`s3cmd du s3://backup-mysqldumps/$dump_dir/ | cut -d " " -f 2`
size_files_s3=`s3cmd du s3://backup-mysqldumps/$dump_dir/ | cut -d " " -f 1`

# Tell zabbix the S3 stats and that the script ended.
z_out_c_s3=`$zabbix_sender -k BKP[dumps,count_s3] -o $cnt_files_s3`
z_out_s_s3=`$zabbix_sender -k BKP[dumps,size_s3] -o $size_files_s3`
z_out_end=`$zabbix_sender -k BKP[proc,started] -o 0`

echo -e "$(timestamp) Z[COUNT]: $cnt_files" >> $log_file
echo -e "$(timestamp) Z[SIZE]: $size_files" >> $log_file
echo -e "$(timestamp) Z[COUNT_S3]: $cnt_files_s3" >> $log_file
echo -e "$(timestamp) Z[SIZE_S3]: $size_files_s3" >> $log_file
echo -e "$(timestamp) Z[END]: 0" >> $log_file


msg_end="$(timestamp) End of $0 vars: \n\t TOTAL DB DUMPED TODAY:[$cnt_files]\n\t \n"
echo -e $msg_end >> $log_file

