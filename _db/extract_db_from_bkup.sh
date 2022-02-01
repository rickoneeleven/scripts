#!/bin/bash

DATE=`date +%y.%m.%d`
echo
echo cronjob as root running on debs server, extracting backup zip file for fghgf for $DATE to rick111/tmp
tar xvzf /home/rick111/easyremote_backup/$DATE/fghgf.com.tar.gz -C /home/rick111/temp/

echo
echo now extracting the database file from the .gz file
gunzip /home/rick111/temp/fghgf.com_mysql_fghgf.gz

echo
echo now moving the database to rick111 dumps
mv /home/rick111/temp/fghgf.com_mysql_fghgf /home/rick111/111/dumps/fghgf.sql

echo
echo deleting everything from rick111/temp
rm /home/rick111/temp/* -rf

echo
echo script complete, please note this does NOT import the database, only moves the extracted one to "dumps"
