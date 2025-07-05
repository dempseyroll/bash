#!/bin/bash

THRESHOLD=80
DISK_USAGE=$(df / | grep / | awk '{print $5}' | sed 's/%//')

if [ "$DISK_USAGE" -gt "$THRESHOLD" ]; then
    echo "Disk usage is above $THRESHOLD%. Current usage: $DISK_USAGE%" | mail -s "Disk Usage Alert" your_email@example.com
fi

# Cron every hour: 0 * * * * /path/to/disk-usage-alert.sh