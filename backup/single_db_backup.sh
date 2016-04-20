#!/bin/bash

OPTS=`getopt -o d:i:h --long do-db:,ignore-table:,help -n 'dump-options' -- "$@"`

if [ $? != 0 ] ; then echo "Failed parsing options." ; exit 1 ; fi

eval set -- "$OPTS"

while true; do
        case "$1" in
        -h | --help)
                echo "usage $0 -d | --do-db=<database_name>, -i | --ignore-table=<table_name>"
                shift;;
        -d | --do-db)
                if [ -n "$2" ];
                then
                        DO_DB="$2"
                fi
                shift 2;;
        -i | --ignore-table)
                if [ -n "$2" ];
                then
                        IGNORE_TABLE="$2"
                fi
                shift 2;;
        --)
        #       echo "usage $0 -d | --do-db=<database_name>, -i | --ignore-table=<table_name>"
                shift
                break;;
        esac
done


# this is a parallel mysqldump lbzip2 script for hourly backups
# files must be in format <DB_NAME>.`date '+%d%b%Y'`.bz2
dump_timestamp=`date '+%d%b%Y-%Hh%Mm'`
dump_date=`date '+%d%b%Y'`

mysql_slave='axs-db-1'
#mysql_slave='axs-db-2'
cpu_cores="16" # cpus of host running this proccess

backup_dir="/backup/mysqldumps_single_db/"

log_file="/backup/log/single_db_backup_v2.$dump_date.log"

#zabbix_proxy_host="10.1.1.2"
#zabbix_proxy_port="10051"
#zabbix_item_count="BKP[dumps,count]"
#zabbix_item_size="BKP[dumps,size]"

#zabbix_sender="/usr/bin/zabbix_sender -z $zabbix_proxy_host -p $zabbix_proxy_port -s AXS-SYS-BACKUP "

# mail part depreced

#mail vars
#mail_subj="VCLOUD: Backup Report [MySQL DUMP] for $dump_timestamp"
#mail_to="sysadmin@axsmarine.com"


#timestamp function
timestamp() {
        date +"%T"
}

# Tell zabbix server that script is running (key is boolean)
#z_out_start=`$zabbix_sender -k BKP[proc,started] -o 1`

msg_start="$(timestamp) Starting $0 vars: \n\t SLAVE:[$mysql_slave]\n\t DIR:[$backup_dir]\n\t CPU:[$cpu_cores]\n\t LOG:[$log_file]\n"
#start log to file
echo -e $msg_start >> $log_file
echo -e "$(timestamp) [START] SIGNEL DUMP DO_DB:[$DO_DB] IGNORE_TABLE:[$IGNORE_TABLE]\n" >> $log_file
#log to stdout
#echo -e $msg_start
FILENAME="$backup_dir""$DO_DB"."wo"."$IGNORE_TABLE"."$dump_timestamp.bz2"

/usr/bin/mysqldump -h $mysql_slave --routines --triggers --events --skip-comments --single-transaction $DO_DB --ignore-table $DO_DB.$IGNORE_TABLE  | /usr/bin/lbzip2 > $FILENAME

#cd $backup_dir
#cnt_files=`ls -al *$dump_timestamp*.bz2 | wc -l`
#size_files=`du -bsc *$dump_timestamp*.bz2 | grep total | awk -F' ' '{print $1}'`

# mail part depreced

#body0="$msg_start\n"
#body1="$msg_end\n"

#body="$body0\n$body1"

#echo -e $body | mutt -a "$log_file" -s "$mail_subj" -- $mail_to

# Tell zabbix the current variables and that script ends
#z_out_c=`$zabbix_sender -k BKP[dumps,count] -o $cnt_files`
#z_out_s=`$zabbix_sender -k BKP[dumps,size] -o $size_files`
#z_out_end=`$zabbix_sender -k BKP[proc,started] -o 0`

#echo -e "$(timestamp) Z[COUNT]: $cnt_files" >> $log_file
#echo -e "$(timestamp) Z[SIZE]: $size_files" >> $log_file
echo -e "$(timestamp) [END]: 0" >> $log_file


msg_end="$(timestamp) End of $0 vars: \n\t TOTAL DB DUMPED TODAY:[$cnt_files]\n\t \n"
echo -e $msg_end >> $log_file
#echo -e $msg_end

