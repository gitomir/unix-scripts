#!/bin/bash

# this is a parallel mysqldump lbzip2 script for hourly backups
# files must be in format <DB_NAME>.`date '+%d%b%Y'`.bz2
dump_timestamp=`date '+%d%b%Y-%Hh'`
dump_date=`date '+%d%b%Y'`

mysql_slave='aws-db-3'
cpu_cores="7" # cpus of host running this proccess

#backup_dir="/backup/mysqldumps/"
backup_dir="/backup/s3-mysqldumps/"

log_file="/backup/log/backup_v2.$dump_date.log"

zabbix_proxy_host="10.10.0.10"
zabbix_proxy_port="10051"
zabbix_item_count="BKP[dumps,count]"
zabbix_item_size="BKP[dumps,size]"

zabbix_sender="/usr/bin/zabbix_sender -z $zabbix_proxy_host -p $zabbix_proxy_port -s AWS-BACKUP "

# mail part depreced

#mail vars
#mail_subj="VCLOUD: Backup Report [MySQL DUMP] for $dump_timestamp"
#mail_to="sysadmin@axsmarine.com"


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
#echo -e $msg_start

/usr/bin/mysql -h $mysql_slave -e 'show databases' -s --skip-column-names \
        | /bin/egrep -iv "^(test|TEST|performance_schema|information_schema)\$" \
        | /usr/bin/parallel --gnu -j$cpu_cores "/usr/bin/mysqldump -h $mysql_slave --routines --triggers --events --skip-comments --single-transaction {} | /usr/bin/lbzip2 > $backup_dir{}.$dump_timestamp.bz2"

cd $backup_dir
cnt_files=`ls -al *$dump_timestamp*.bz2 | wc -l`
size_files=`du -bsc *$dump_timestamp*.bz2 | grep total | awk -F' ' '{print $1}'`

# mail part depreced

#body0="$msg_start\n"
#body1="$msg_end\n"

#body="$body0\n$body1"

#echo -e $body | mutt -a "$log_file" -s "$mail_subj" -- $mail_to

# Tell zabbix the current variables and that script ends
z_out_c=`$zabbix_sender -k BKP[dumps,count] -o $cnt_files`
z_out_s=`$zabbix_sender -k BKP[dumps,size] -o $size_files`
z_out_end=`$zabbix_sender -k BKP[proc,started] -o 0`

echo -e "$(timestamp) Z[COUNT]: $cnt_files" >> $log_file
echo -e "$(timestamp) Z[SIZE]: $size_files" >> $log_file
echo -e "$(timestamp) Z[END]: 0" >> $log_file


msg_end="$(timestamp) End of $0 vars: \n\t TOTAL DB DUMPED TODAY:[$cnt_files]\n\t \n"
echo -e $msg_end >> $log_file
#echo -e $msg_end

