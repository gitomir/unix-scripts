#!/bin/bash
#===============================================
# 
# Startup script for ionic with screen wrapper 
#
#
# Author : mnikolov@santech.fr
# Version: 20160728
#
#===============================================

BASE=/data/jenkins/workspace/STAGING-CNAMTS-Frontend/mobile
ENV="staging"

PID=$BASE/ionic-$ENV.pid
LOG=$BASE/ionic-$ENV.log
ERR=$BASE/ionic-$ENV.err

OPT="serve --lab --all -p 8080 -s -c -w -b --nolivereload"
CMD="ionic $OPT"

USR=root

# colors
red='\e[0;31m'
green='\e[0;32m'
yellow='\e[0;33m'
reset='\e[0m'

echoRed() { echo -e "${red}$1${reset}"; }
echoGreen() { echo -e "${green}$1${reset}"; }
echoYellow() { echo -e "${yellow}$1${reset}"; }

status() {
    if [ -f $PID ]
    then
        echoGreen "[STATUS] OK : PID:[$( cat $PID )] FILE: [$PID]";
        echo $(ps -ef | grep -v grep | grep $( cat $PID )) >> $LOG
        exit 0
    else
        echoRed "[STATUS] NO Pid file :("
        exit 1
    fi
}

start() {
    if [ -f $PID ]
    then
        echoRed "[START] Already started. PID: [$( cat $PID )]"
    else
        touch $PID
        echoYellow "[START] (nohup screen -m -d -L $CMD)"
        if nohup screen -m -d -L $CMD >>$LOG 2>&1 &
        then $(ps -ef | grep -v grep | grep "$CMD" | grep -w $USR | awk '{print $2}' > $PID)
            echoGreen "[START] OK"
            echo "$(date '+%Y-%m-%d %X'): START (nohup screen -m -d -L $CMD)" >>$LOG
        else 
            echoRed "[START] Error starting (nohup screen -m -d -L $CMD)... removing pid."
            /bin/rm -f $PID
        fi
    fi
}

stop() {
    MSG="Killing "
    LIST=$(ps -ef | grep -v grep | grep "$CMD" | grep -w $USR | awk '{print $2}')
    if [ "$LIST" ]
        then
            echoYellow "[STOP] $MSG $LIST ..."
            echo $LIST | xargs kill -9
            if [ -f $PID ]
            then
                echoYellow "[STOP] Removing $PID file ..."
                /bin/rm -f $PID
            fi
        else
           echoRed "[STOP] No process killed... Removing pid file $PID"
           /bin/rm -f $PID
    fi 
}

case "$1" in
    'start')
            start
            ;;
    'stop')
            stop
            ;;
    'restart')
            stop ; echoYellow "Sleeping..."; sleep 1 ;
            start
            ;;
    'status')
            status
            ;;
    *)
            echo
            echo "Usage: $0 { start | stop | restart | status }"
            echo
            exit 1
            ;;
esac

exit 0