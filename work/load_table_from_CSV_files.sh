#!/bin/bash
# 1) All the files must be in the same directory.
# 2) MySQL credentials are environment variables in root account.
# 3) Execute as root.
### VARIABLES ###
LIST=$(aws s3 ls s3://YOUR_BUCKET/ | awk -F " " '{print $4}')
COUNT=0
TABLE_NAME="YOUR_TABLE"
### --- START BATCH PROCESSING --- ###
echo "$(date +%d-%m-%Y" "%H:%M:%S) INFO: START SCRIPT"
echo "$(date +%d-%m-%Y" "%H:%M:%S) INFO: Creating secondary table..."
./create_table_backup.sh
echo "$(date +%d-%m-%Y" "%H:%M:%S) INFO: Table $TABLE_NAME created."
echo "$(date +%d-%m-%Y" "%H:%M:%S) INFO: Begin batch processing..."
for FILE in $LIST;
do
        echo "Downloading: $FILE"
        aws s3 cp s3://YOUR_BUCKET/$FILE ./
        ### Saving count rows from CSV file to control
        wc -l $FILE  | cut -d " " -f1 >> control_row_sum.txt
        ########
        mysql -u$MYSQL_USER -p$MYSQL_PASS --local-infile $MYSQL_DATABASE -e "LOAD DATA LOCAL INFILE '$FILE' INTO TABLE $TABLE_NAME FIELDS TERMINATED BY ',' LINES TERMINATED BY '\n'"
        COUNT=COUNT+1
        rm -f $FILE
done;
echo "$(date +%d-%m-%Y" "%H:%M:%S) INFO: Ended batch process. $COUNT files were loaded."
### Control of rows inserted ###
SUM=$(awk '{sum += $1} END {print sum}' control_row_sum.txt)
echo "$(date +%d-%m-%Y" "%H:%M:%S) INFO: Total rows inserted from CSV files: $SUM"
###################################################
### --- Adding constraints and renaming_tables  --- ###
echo "$(date +%d-%m-%Y" "%H:%M:%S) INFO: Executing alter_table script...."
mysql -h localhost -u$MYSQL_USER -p$MYSQL_PASS $MYSQL_DATABASE < alter_table.sql
echo "$(date +%d-%m-%Y" "%H:%M:%S) INFO: alter_table execution finished."
###################################################
### --- END BATCH PROCESSING --- ###
echo "$(date +%d-%m-%Y" "%H:%M:%S) INFO: END SCRIPT."

