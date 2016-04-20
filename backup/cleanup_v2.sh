#!/bin/bash

date_now=`date '+%d%b%Y'`
date_now_dash=`date '+%d-%b-%Y'`
date_now_uts=`date -d "$date_now" '+%s'`

days_to_keep="3" #5days (4th and 5th days keep only -23h snapshot
days_to_keep_full="3" #3days of full */4h snapshots

date_dmin=$(date --date="$days_to_keep days ago" +"%d-%b-%Y")
date_dmin_uts=`date -d "$date_dmin" '+%s'`
date_dmin_full=$(date --date="$days_to_keep_full days ago" +"%d-%b-%Y")
date_dmin_full_uts=`date -d "$date_dmin" '+%s'`

backup_dir="/backup/mysqldumps/"

log_file="/backup/log/cleanup.$date_now.log"

zabbix_proxy_host="10.10.0.10"
zabbix_proxy_port="10051"
zabbix_item_files_kept="BKP[dumps,kept]"
zabbix_item_files_deleted="BKP[dumps,deleted]"
zabbix_item_files_errors="BKP[dumps,errors]"

zabbix_sender="/usr/bin/zabbix_sender -z $zabbix_proxy_host -p $zabbix_proxy_port -s AXS-SYS-BACKUP "


#mail vars
#mail_subj="VCLOUD: Backup Report [CLEANUP] for $date_now_dash"
#mail_to="sysadmin@axsmarine.com"
#mail_to="miroslav.nikolov@axsmarine.com"

#empty counters
cnt_old_files=0
cnt_keep_files=0
cnt_wrong_files=0

#timestamp function
timestamp() {
        date +"%T"
}

msg_start="$(timestamp) Starting $0 on $backup_dir vars: \n\t DAYS TO KEEP:[$days_to_keep days]\n\t DATE NOW:[$date_now_dash/$date_now_uts]\n\t DATE MIN-KEEP:[$date_dmin/$date_dmin_uts]\n\t DATE FULL-KEEP:[$date_dmin_full/$date_dmin_full_uts]\n\t LOG TO:[$log_file]\n"
#start log to file
echo -e $msg_start >> $log_file
#log to stdout
echo -e $msg_start

# TESTAMENT: first clean up snapshots older than days_to_keep

cd $backup_dir

for file in `find $backup_dir -maxdepth 1 -name "*.bz2" -printf "%P\n"`; do
        file_date=`ls $file | awk -F. '{print $2}' | awk -F- '{print $1}' | sed 's/\([0-9]\+\)\([a-zA-Z]\+\)\([0-9]\+\)/\1-\2-\3/' `

#       echo $file_date
        #test if var is date
        #date format DD-Mmm-YYY
        if [[ $file_date =~ [0-9][0-9]-[A-Z][a-z][a-z]-[0-9][0-9][0-9][0-9] ]];
        then
                file_date_uts=`date -d "$file_date" '+%s'`
                if [ "$file_date_uts" \< "$date_dmin_full_uts" ]
                then
                        echo "$(timestamp) $0 on $backup_dir [DEL] => $file is OLD! [$file_date_uts IS < $date_dmin_uts && $file_date < $date_dmin]" >> $log_file
                        rm -fv $file >> $log_file
                        (( cnt_old_files++))
                else
                        # TESTAMENT: then we keep only 23h snapshots from day 4 and 5 and keep all other 3 days
                        if [ "$file_date_uts" \> "$date_dmin_uts" ]
                        then
                                echo "$(timestamp) $0 on $backup_dir [KEP] => $file is FULL RECENT [$file_date_uts IS > $date_dmin_uts && $file_date > $date_dmin]" >> $log_file
                                (( cnt_keep_files++ ))
                        else
                                # TESTAMENT: check if its nightly snapshot
                                ff_snapshot_hour=`ls $file | awk -F. '{print $2}' | awk -F- '{print $2}'`
                                if [[ $ff_snapshot_hour == "23h" ]]
                                then
                                        echo "$(timestamp) $0 on $backup_dir [KEP] => $file is NIGHTLY RECENT [$file_date_uts IS < $date_dmin_full_uts && $file_date < $date_dmin_full]" >> $log_file
                                        (( cnt_keep_files++ ))
                                else
                                        echo "$(timestamp) $0 on $backup_dir [DEL] => $file is OLD! (NOT A NIGHTLY SNAPSHOT) " >> $log_file
                                        rm -fv $file >> $log_file
                                        (( cnt_old_files++ ))
                                fi
                                # eventually remove file
                        fi

                        # depreced
                        #echo "$(timestamp) $0 on $backup_dir => $file is RECENT [$file_date_uts IS > $date_dmin_uts && $file_date > $date_dmin]" #>> $log_file
                        #(( cnt_keep_files++ ))
                fi
        else
                (( cnt_wrong_files++ ))
        fi

done


#body0="$msg_start\n"
#body1="$msg_end\n"

#body="$body0$body1"

#echo -e $body | mutt -a "$log_file" -s "$mail_subj" -- $mail_to

# Tell zabbix the current variables and that script ends
z_out_k=`$zabbix_sender -k BKP[dumps,kept] -o $cnt_keep_files`
z_out_d=`$zabbix_sender -k BKP[dumps,deleted] -o $cnt_old_files`
z_out_e=`$zabbix_sender -k BKP[dumps,errors] -o $cnt_wrong_files`

echo -e "Z[KEPT]: $z_out_k" >> $log_file
echo -e "Z[DELETED]: $z_out_d" >> $log_file
echo -e "Z[ERRORS]: $z_out_e" >> $log_file

msg_end="$(timestamp) End of $0 vars: \n\t TOTAL OLD FILE:[$cnt_old_files]\n\t TOTAL GOOD FILE:[$cnt_keep_files]\n\t ERROR DATE:[$cnt_wrong_files]\n"
echo -e $msg_end >> $log_file
echo -e $msg_end

#EOF
