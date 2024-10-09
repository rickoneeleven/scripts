#!/bin/bash
DAVE="$(ssh -q -o "BatchMode=yes" rick111@home.novascore.io -p13 "echo 2>&1" && echo $host SSH_OK || echo $host SSH_NOK | tail -n1)"

#all the star and double bracket shit is becauses the initial declaration of DAVE contains whitespace or some
#shit at the start, so the if statement below is doing an, if contains, rather than direct compare.
if [[ "${DAVE}" == *"SSH_OK"* ]]; then
rsync -avzO --no-perms /home/rick111/home_folder_backup/ -e 'ssh -p13' rick111@home.novascore.io:/home/rick111/backup/novascore/
else
    echo "${DAVE}"
    echo "unable to backup /home/rick111 as ssh connection failed"
fi

