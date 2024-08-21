#!/bin/bash
# Albert Lombarte
# Docs: http://www.harecoded.com/copycloneduplicate-mysql-database-script-2184438

#Partoburger notes
#Req: make sure you have MySQL 5.6 or above so you can;
#First run "mysql_config_editor set --user=root --password" first which will created a config file
#for auto connect with hashed/encrypted? config file (.mylogin.cnf), you can then run mysql without any credentials.
 
cp /root/db_clone.sh /home/rick111/111/scripts/
PRODUCTION_DB=novascore
# The following database will be DELETED first:
COPY_DB=novascore_copy
ERROR=/root/duplicate_mysql_error.log
echo "Droping '$COPY_DB' and generating it from '$PRODUCTION_DB' dump"
mysql -e "drop database $COPY_DB;" --force ; mysql -e "create database $COPY_DB;" && mysqldump --force --log-error=$ERROR $PRODUCTION_DB | mysql $COPY_DB
mysql -e "GRANT ALL PRIVILEGES ON novascore_copy.* TO 'db_dave455.novas'@'%' WITH GRANT OPTION;"
echo "cat'ing the error log file, if no errors below, you're golden..."
cat $ERROR
