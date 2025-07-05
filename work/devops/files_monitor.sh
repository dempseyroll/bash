#!/bin/bash
#oldIFS=$IFS
#IFS=$'\n'

# La variable FILE puede tener un txt con los archivos que nos interesen y recorrerlo con un bucle for para vigilar 
# cada archivo
#LIST=`ls -lhtr /home/ec2-user/MNV/files_monitor/ | awk -F " " '{print $9}' > list_files.txt`
while true
do
	WORK_PATH=/home/ec2-user/MNV/files_monitor
	LIST=list_files.txt
	HOSTNAME=$(hostname)
	WHO=$(who)
	
	COMPARE_DATE=`date -d "-10 seconds" "+%Y-%m-%d %H:%M:%S:%s"`
	for FILE in $(sudo cat $WORK_PATH/$LIST);do
		MOD_DATE=`sudo stat $FILE | egrep "(Modify)" | awk -F " " '{print $2, $3}'`
		CHG_DATE=`sudo stat $FILE | egrep "(Change)" | awk -F " " '{print $2, $3}'`
		if [[ "$MOD_DATE" > "$COMPARE_DATE" || "$CHG_DATE" > "$COMPARE_DATE" ]];then
			sudo logger -t files_monitor.sh -e "Un archivo ha sido modificado.\n$FILE;$HOSTNAME;$MOD_DATE;$WHO"
		fi
	done
	sleep 10
done

#IFS=$oldIFS