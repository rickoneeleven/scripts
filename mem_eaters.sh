#!/bin/bash

perl -le 'sleep rand 2' && ps -eo size,pid,user,command --sort -size | awk '{ hr=$1/1024 ; printf("%13.2f Mb",hr) } { for ( x=4 ; x<=NF ; x++ ) { printf("%s ",$x) } print "" }'|head -n10
