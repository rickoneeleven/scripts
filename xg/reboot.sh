#!/usr/bin/expect -f
spawn ssh <XG IP> -l admin
expect "password:"
send "<Admin Password>\r"
expect "Select Menu Number \\\[0-7\\\]:"
send "7\r"
expect "Shutdown(S/s) or Reboot(R/r) Device  (S/s/R/r):  No (Enter) >"
send "r\r"
expect eof
exit
