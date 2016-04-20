#!/bin/bash

LOG_FILE='/data/bin/fetch-mysqldatadir.log'
MYSQL_LOCAL_DATADIR='/tmp/mysql'
MYSQL_REMOTE_DATADIR='/tmp/mysqlr'

MYSQL_LOCAL_FS=`echo $MYSQL_LOCAL_DATADIR | awk -F/ '{ print $2; }'`

OPTS=`getopt -o d:i:h --long db-host:,ignore-db:,help -n 'dump-options' -- "$@"`

if [ $? != 0 ] ; then echo "Failed parsing options." ; exit 1 ; fi

eval set -- "$OPTS"

while true; do
        case "$1" in
        -h | --help)
                echo "usage $0 -d | --db-host=<database_hostname>, -i | --ignore-db=<database_name> (NOT IMPLEMENTED YET)"
                shift;;
        -d | --db-host)
                if [ -n "$2" ];
                then
                        DB_HOST="$2"
                fi
                shift 2;;
#        -i | --ignore-db)
#                if [ -n "$2" ];
#                then
#                        IGNORE_DB="$2"
#                fi
#                shift 2;;
        --)
#                echo "usage $0 -d | --db-host=<database_host>"
                shift
                break;;
        esac
done

if [ -z $DB_HOST ]; then
        echo "missing DB HOST option"
        exit
fi

#timestamp function
timestamp() {
        date +"%T"
}


echo -e "$(timestamp) [START] $0 with DB-HOST -> [$DB_HOST]" >> $LOG_FILE
echo -n "$(timestamp) [RUN] stopping mysql service on localhost ..." >> $LOG_FILE

#service mysql stop > /dev/null 2>&1

RESULT=$(service mysql status)

if [ "$RESULT" == " * MySQL is not running" ]; then
        echo -e "stopped [OK!]" >> $LOG_FILE
else
        echo -e "mysql is still running [ERR]" >> $LOG_FILE
        echo "$(timestamp) [STOP] ERROR mysql is still running" >> $LOG_FILE
#       exit
fi

echo -n "$(timestamp) [RUN] removing old mysql datadir -> [$MYSQL_LOCAL_DATADIR] ..." >> $LOG_FILE

RESULT=$(rm -vfr $MYSQL_LOCAL_DATADIR | awk -F: '{ print $1}')

if [ "$RESULT" == "removed directory" ]; then
        echo -e "$RESULT $MYSQL_LOCAL_DATADIR [OK!]" >> $LOG_FILE
else
        echo -e "no output of rm command. check fs $MYSQL_LOCAL_DATADIR [ERR]" >> $LOG_FILE
        echo "$(timestamp) [STOP] ERROR no output of rm command. check fs $MYSQL_LOCAL_DATADIR" >> $LOG_FILE
#       exit
fi


echo -n "$(timestamp) [RUN] Checking available space on localhost -> [/$MYSQL_LOCAL_FS/] ..." >> $LOG_FILE

RESULT=$(df -h | grep $MYSQL_LOCAL_FS | awk -F' ' '{ print $4; }')
FREE_SPACE_LOCAL=$RESULT

echo -e "FREE SPACE -> [$RESULT]" >> $LOG_FILE

echo -n "$(timestamp) [RUN] Checking used space $DB_HOST -> [$MYSQL_REMOTE_DATADIR] ..." >> $LOG_FILE

#FIXME hardcoded mapper data
RESULT=$(ssh $DB_HOST 'df -h | grep mapper | grep data | awk -F" " '"'"'{ print $3 }'"'"'')
USED_SPACE_REMOTE=$RESULT

echo -n "USED SPACE -> [$RESULT]" >> $LOG_FILE

if [ $(echo "${FREE_SPACE_LOCAL//G/} > ${USED_SPACE_REMOTE//G/}" | bc) -eq 1 ]; then
        echo -e " sufficent [OK!]" >> $LOG_FILE
else
        echo "$(timestamp) [ERR] Not enought free space on localhost [$FREE_SPACE_LOCAL] < [$USED_SPACE_REMOTE] [ERR]" >> $LOG_FILE
#       exit
fi

#FIXME works only for one VG
echo -n "$(timestamp) [RUN] Checking for available free LVM space on $DB_HOST ..." >> $LOG_FILE

RESULT=$(ssh $DB_HOST 'vgdisplay' | grep Free | awk -F/ '{ print $3}' | sed -e 's/^[[:space:]]*//')
FREE_SPACE_SS=$RESULT

echo -e "FREE VG SPACE -> [$RESULT]" >> $LOG_FILE

if [ $(echo "${FREE_SPACE_SS//GiB/} > 20" | bc) -eq 1 ]; then
        echo -n " sufficent [OK!]" >> $LOG_FILE
else
        echo "$(timestamp) [ERR] Not enought free PE on LVM [$FREE_SPACE_SS] < 20GiB [ERR]" >> $LOG_FILE
#       exit
fi

echo -n "$(timestamp) [RUN] Running MySQL FLUSH TABLES WITH READ LOCK ..." >> $LOG_FILE

RESULT=$(ssh $DB_HOST 'mysql -uuser1 -pcrim73 -e "FLUSH TABLES WITH READ LOCK; SELECT SLEEP(15); UNLOCK TABLES;" >/dev/null &')

#FIXME shot it the dark ...
echo -e " LOCKED for 15s [OK!]" >> $LOG_FILE

echo -n "$(timestamp) [RUN] Creating 20G lvm-snapshot of /dev/vgdata/lvdata ..." >> $LOG_FILE

#FIXME hardcoded fs lvdata and remove
RESULT=$(ssh $DB_HOST 'lvcreate -L20G -s -n dbsnapshot /dev/vgdata/lvdata')
RESULT=`echo ${RESULT//\"/} | sed -e 's/^[[:space:]]*//'`


if [ "$RESULT" == 'Logical volume "dbsnapshot" created' ]; then
        echo -n "$RESULT is [OK!]" >> $LOG_FILE
else
        echo "$(timestamp) [ERR] cannot create lvn-snapshot output->[$RESULT] [ERR]" >> $LOG_FILE
fi

exit

echo -n "$(timestamp) [RUN] Mounting the snapshot to /mnt/snapshot ..." >> $LOG_FILE

RESULT=$(ssh $DB_HOST 'mount /dev/vgdata/dbsnapshot /mnt/snapshot')

echo -e "$RESULT [OK!]" >> $LOG_FILE

echo -n "$(timestamp) [RUN] Starting local rsync to fetch snapshot from root@$DB_HOST:/mnt/snapshot to $MYSQL_LOCAL_DATADIR" >> $LOG_FILE

RESULT=$(rsync -avprP -e ssh root@DB_HOST:/mnt/snapshot/xtra* $MYSQL_LOCAL_DATADIR)

echo "$(timestamp) ---------------------[RSYNC OUTPUT START]------------------\n$RESULT\n$(timestamp) ------------------[RSYNC OUTPUT END]--------------------\n"

echo -n "$(timestamp) [RUN] Removing lvm-snapshot /dev/vgdata/dbsnapshot ..." >> $LOG_FILE

RESULT=$(ssh $DB_HOST 'lvremove -f /dev/vgdata/dbsnapshot')

echo -e "$RESULT [OK!]"

#EOF
