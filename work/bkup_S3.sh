#!/bin/bash
# Mover logs a S3 con más de 10 días de antigüedad.

oldIFS=$IFS
IFS=$'\n'

WORK_PATH=YOUR_DIR
LIMIT_DATE=`date +%Y-%m-%d --date="-7 days"`

ls -lhtr $WORK_PATH/ | grep ^d | grep -v job_files |awk -F " " '{print $9}' > $WORK_PATH/logs_per_day.txt

for dir in $(cat $WORK_PATH/logs_per_day.txt); do
	if [[ $dir == $LIMIT_DATE ]]; then
		break
	else
		aws s3 sync $WORK_PATH/$dir/ s3://YOUR_BUCKET/YOUR_DIR/$dir/
		ls -lhtr $WORK_PATH/$dir/ | grep -v total |awk -F " " '{print $9}' > $WORK_PATH/check.txt
		for file in $(cat $WORK_PATH/check.txt); do
			MD5=`md5sum $WORK_PATH/$dir/$file | awk -F " " '{print $1}'`
			ETAG=`aws s3api head-object --bucket "YOUR_BUCKET" --key "YOUR_DIR/$dir/$file" | grep ETag | awk -F " " '{print $2}' | tr -d '"\\\",'`
			if [[ $MD5 == $ETAG ]]; then
				sudo rm -f $WORK_PATH/$dir/$file
				continue
			else
				echo -e "$file\n md5sum: $MD5\n ETag: $ETAG" >> $WORK_PATH/s3_bkup_failed_integrity_report.txt
				logger "No coinciden md5sum $MD5 e ETag $ETAG ver archivo en $WORK_PATH/s3_bkup_failed_integrity_report.txt"
				continue
			fi
		done
		sudo rmdir $dir
	fi

done > $WORK_PATH/bkup_s3.log 2>&1


IFS=$oldIFS

# Checksum MD5 compare:

# aws s3api head-object --bucket "[YOUR_BUCKET]" --key "YOUR_DIR/YOUR_FILE" | grep ETag | awk -F " " '{print $2}' | tr -d '"\\",'

