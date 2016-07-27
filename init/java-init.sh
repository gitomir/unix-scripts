#!/bin/bash
#================================
#
# Init  script for java apps
#
# Author : mnikolov@santech.fr
# Version : 20160727
#
#================================

BIN="/data/activemq/consumers/MQC_MAILJET.JAR"
LOG="/data/activemq/consumers/mailjet.log"

ARGS="-jar -Dspring.profiles.active=preprod"

nohup java $ARGS $BIN > $LOG & echo $!
