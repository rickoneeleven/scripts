#!/usr/bin/expect

set timeout -1

# Start the SSH connection
#spawn ssh admin@192.168.1.2
spawn stdbuf -o0 -e0 ssh admin@192.168.1.2

# Wait for the password prompt
expect "*assword:*"
sleep 1
send "<xg password>"

# Wait a bit for the connection to be fully established
sleep 1
send "5\r"

# Wait a moment to ensure the command is processed
sleep 1
send "3\r"

sleep 1
send "mount -o remount,exec /tmp\r"
sleep 1
send "cd /tmp\r"
sleep 1
send "curl -o ns_speedtest_v3.sh https://pinescore.com/111/ns_speedtest_v3.sh -k && chmod +x ns_speedtest_v3.sh && ./ns_speedtest_v3.sh Port2\r"

# Switch to interactive mode
interact
