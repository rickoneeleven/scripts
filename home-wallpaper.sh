#!/bin/bash

xvfb-run --server-args="-screen 0, 1920x1080x24" cutycapt --url=https://home.loopnova.com --out=/tmp/localfile.png --zoom-factor=2
convert /tmp/localfile.png -crop 1791x900+50+80 /home/rick111/111/wallpaper/output.jpg
convert /tmp/localfile.png -crop 1791x1330+50+80 /home/rick111/111/wallpaper/output1.jpg
#cp /home/rick111/111/wallpaper/output* /home/novascore/public_html/111/
