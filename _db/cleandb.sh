#!/usr/bin/env bash
DATABASES="$(mysql -e 'show databases \G' | grep "^Database" | grep -v '^Database: mysql$\|^Database: binlog$\|^Database: performance_schema\|^Database: information_schema' | sed 's/^Database: //g')"
mysqldump --databases $DATABASES -r alldatabases.sql && echo "$DATABASES" | while read -r DB; do
    mysql -e "drop database \`$DB\`"
done && \
    /etc/init.d/mysql stop && \
    find /var/lib/mysql -maxdepth 1 -type f \( -name 'ibdata1' -or -name 'ib_logfile*' \) -delete && \
    /etc/init.d/mysql start && \
    mysql < alldatabases.sql && \
    rm -f alldatabases.sql
