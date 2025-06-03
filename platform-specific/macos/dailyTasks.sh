#!/bin/bash

# Remove files older than 1 day from Downloads
find ~/Downloads -mindepth 1 -mtime +1 -exec rm -r {} +

# Copy SSH config file
cp /Users/rick111/.ssh/config /Users/rick111/OneDrive/backup/

# Log the backup with datetime
{
    /bin/date "+%Y-%m-%d %H:%M:%S" | tr -d '\n'
    echo -n ": "
    echo "backup of ssh config file from macbook so i don't lose ssh config details"
} >> /Users/rick111/OneDrive/backup/log.txt