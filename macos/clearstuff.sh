#!/bin/bash

/usr/bin/find /Users/rick111/.Trash -mindepth 1 -prune -not -newerat '0 days ago' -exec /bin/rm -Rfv {} \;
/usr/bin/find /Users/rick111/Pictures/Photo\ Booth\ Library/Pictures -mindepth 1 -prune -not -newerat '0 days ago' -exec /bin/rm -Rfv {} \;
/usr/bin/find /Users/rick111/Downloads -mindepth 1 -prune -not -newerat '3 days ago' -exec /bin/rm -Rfv {} \;
