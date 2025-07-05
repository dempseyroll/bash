#!/bin/bash

# Backup Directory
SOURCE="/home/mveron/"
DESTINATION="/backup/location/"

# Run rsync to create a backup
rsync -avh --delete $SOURCE $DESTINATION

echo "Backup completed successfully at $(date)"

# Cron 2 AM: 0 2 * * * /path/to/backup-script.sh