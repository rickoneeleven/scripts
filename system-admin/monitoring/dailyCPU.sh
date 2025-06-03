#!/bin/bash
sar -f /var/log/sysstat/sa$(date +%d -d yesterday)
