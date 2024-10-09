#!/bin/bash

#----------------------------------------
echo
DAYOFWEEK=$(date +"%u")
echo DAYOFWEEK: $DAYOFWEEK

if [ "$DAYOFWEEK" -eq 7 ]; 
then
   echo "It's Saturday night lad, not backing up, may cause glitches to any boxing you plan"
   echo on recording. 
else
   DATE=$(date +%Y-%m-%d)
   echo "Starting backup to amazon s3 $(date)"
   echo "grepping lines which have the date:${DATE} in them, to show only files sync'd today"
   /root/.local/bin/aws s3 sync --delete --quiet --sse AES256 /home/rick111 s3://ns-home-folder-backup/
   echo
   echo "Finished backup to amazon s3 $(date)"
   echo
   /root/.local/bin/aws s3 ls s3://ns-home-folder-backup/ --recursive --human-readable --summarize | grep "${DATE}\|Total"
fi
#---------------------------------------
