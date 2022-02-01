#!/bin/bash
echo Creds required for pinescore DB, sql user is root
mysqldump -u root -p pinescore > ~/pinescore.sql
echo Creds required for dev DB, sql user is root
mysqldump -u root -p dev > ~/dev.sql
php-mysql-diff diff ~/pinescore.sql ~/dev.sql
read -n1 -r -p "Press any key to dump pinescore data to dev database" key
mysql -u root -p dev < ~/pinescore.sql
rm ~/pinescore.sql
rm ~/dev.sql
echo it is done.
