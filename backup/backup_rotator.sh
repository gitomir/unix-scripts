#!/bin/bash
backupdir="/sofia-nas/mysqldumps/"
dir_to_move_old_files=$backupdir"scheduled_for_remove/"
keepdays="30"

back_date=$(date --date="$keepdays days ago" +"%d-%b-%Y")
back_date_uts=`date -d "$back_date" '+%s'`

cnt_keep_files=0
cnt_move_files=0
cnt_wrong_files=0

#echo "current date->$current_date"
#echo "back date->$back_date, unix timestamp->$back_date_uts"

echo $dir_to_move_old_files
exit

for i in `ls *.gz`; do
#       echo "input->$i"
        cda=`ls $i | awk -F. '{print $2}' | sed 's/\([0-9]\+\)\([a-zA-Z]\+\)\([0-9]\+\)/\1-\2-\3/' `
#       echo "cda->$cda"
        #date format DD-Mmm-YYY
        if [[ $cda =~ [0-9][0-9]-[A-Z][a-z][a-z]-[0-9][0-9][0-9][0-9] ]];
        then
                cds=`date -d "$cda" '+%s'`
                if [ "$cds" \< "$back_date_uts" ]
                then
#                       echo "move $i to $dir_to_move_old_files"
                        mv $i $dir_to_move_old_files
                        (( cnt_move_files++))
                else
#                       echo "keep $i"
                        (( cnt_keep_files++ ))
                fi
        else
#               echo "WRONG STR $cda"
                (( cnt_wrong_files++ ))
        fi

done

echo "SUMMARY: KEEP-$cnt_keep_files ; MOVE-$cnt_move_files ; WRONG-$cnt_wrong_files"
exit
