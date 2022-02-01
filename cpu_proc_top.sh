ps -Ao user,uid,comm,pid,pcpu,tty --sort=-pcpu | head -n 6 | column -t
