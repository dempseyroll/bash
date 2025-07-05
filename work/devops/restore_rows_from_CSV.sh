#!/bin/bash
# This allows restore some rows missing on YOUR_TABLE.
# 1) All the files must be in the same directory.
# 2) MySQL credentials are environment variables in root account.
# 3) Execute as root.
BUCKET_PATH="s3://BUCKET-PATH"
FILE_SOURCE="id_missing.txt" # THIS IS YOUR FILE WITH YOUR ID YOU WANT ONLY! ONE NUMBER FOR EACH LINE PLS.
ROWS_TO_LOAD="rows_to_load.csv"
TABLE_NAME="YOUR_TABLE"
LIST=$(aws s3 ls s3://BUCKET-PATH | awk -F " " '{print $4}')
echo "$(date +%d-%m-%Y" "%H:%M:%S) INFO: STARTING RESTORE PROCESS..."
### --- START LOOKING FOR ROWS IN S3 CSV FILES --- ###
echo "$(date +%d-%m-%Y" "%H:%M:%S) INFO: Starting row search in S3 bucket..."
for ROW in $FILE_SOURCE;
do
        for FILE in $LIST;
        do
                # Local variables
                FIRST_ID=$(aws s3 cp $BUCKET_PATH$FILE - 2> /dev/null | head -1 | awk -F "," '{print $1}')
                LAST_ID=$(aws s3 cp $BUCKET_PATH$FILE - 2> /dev/null | tail -1 | awk -F "," '{print $1}')
                echo "Reviewing: $FILE"
                if [[ $ROW -ge $FIRST_ID ]] && [[ $ROW -le $LAST_ID ]]
                then
                        aws s3 cp $BUCKET_PATH$FILE - 2> /dev/null | grep "^$ROW," >> $ROWS_TO_LOAD
                        echo "$(date +%d-%m-%Y" "%H:%M:%S) INFO: One row match for $ROW in file $FILE. Row added successfully."
                        break
                else
                        continue
                fi
        done;
done;

### --- Load rows to table DB --- ###
# WARN: Uncomment next line when you can test this script.
#mysql -u$MYSQL_USER -p$MYSQL_PASS --local-infile $MYSQL_DATABASE -e "LOAD DATA LOCAL INFILE '$ROWS_TO_LOAD' INTO TABLE $TABLE_NAME FIELDS TERMINATED BY ',' LINES TERMINATED BY '\n'"
COUNT_ID=$(wc -l $FILE_SOURCE | cut -d " " -f1)
COUNT_ROW=$(wc -l $ROWS_TO_LOAD | cut -d " " -f1)
echo "$(date +%d-%m-%Y" "%H:%M:%S) INFO: RESTORE PROCESS ENDED. YOU HAVE RESTORED $COUNT_ROW ROWS FROM $COUNT_ID LISTED IN YOUR FILE."

