#!/bin/sh
# version: 1.3

#
SERVER="github.axs-offices.com"                      
GZNAME="ghe-axs-backup"               
FL2KEP=5                                         
DIROUT="/sofia-nas/github_backups/"                      
BAKUPS="/sofia-nas/github_backups/archive"                      
SLPTME=20                                          


# Save our script path
SCRIPTPATH=`pwd`



# Create our backup files
#
echo "1) Exporting GitHub Enterprise backup"
ssh "admin@"$SERVER "'ghe-maintenance -s'"
ssh "admin@"$SERVER "'ghe-export-authorized-keys'" > $DIROUT"ghe-authorized-keys.json"
ssh "admin@"$SERVER "'ghe-export-es-indices'" > $DIROUT"es-indices.tar"
ssh "admin@"$SERVER "'ghe-export-mysql'" | gzip > $DIROUT"enterprise-mysql-backup.sql.gz"
ssh "admin@"$SERVER "'ghe-export-redis'" > $DIROUT"backup-redis.rdb"
ssh "admin@"$SERVER "'ghe-export-settings'" > $DIROUT"settings.json"
ssh "admin@"$SERVER "'ghe-export-ssh-host-keys'" > $DIROUT"host-keys.tar"
ssh "admin@"$SERVER "'ghe-export-repositories'" > $DIROUT"enterprise-repositories-backup.tar"
sleep $SLPTME"m"
ssh "admin@"$SERVER "'ghe-maintenance -u'"


# Package our files by the date
#
echo "2) Packaging the files"
CURRENT_DATE="$(date +%Y.%m.%d_%H-%M)"     
FILENAME=$GZNAME"-"$CURRENT_DATE.tgz   
cd $DIROUT                          
tar cvfW $FILENAME ghe-*                 
mv $FILENAME $BAKUPS/              
cd $SCRIPTPATH                    


# Keeps the last 'FL2KEP' of files
#
echo "3) Location clean up"
cd $BAKUPS
for i in `ls -t ghe-* | tail -n+2`; do
ls -t * | tail -n+$(($FL2KEP + 1)) | xargs rm -f
done


echo "--done--"
exit 0
