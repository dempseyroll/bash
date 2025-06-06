#!/bin/bash
#Backup del separador de campo para modificarlo luego por el ciclo for:
oldIFS=$IFS
IFS=$'\n'

today=`date +%Y-%m-%d`
today_directory=`mkdir $today`
cut_date_today=`date | awk -F " " '{print $2" "$3}'`

# Creación del directorio donde van los logs del día:
$today_directory

# Movimiento de los archivos
#ls -lhtr | awk -F " " '{print $6" "$7" "$9}' > list_files.txt
ls -lhtr server.log.* > list_files.txt

for line in $(cat list_files.txt); do
	coincidence=`echo "$line" | awk -F " " '{print $6" "$7}'`
	if [[ "$coincidence" == "$cut_date_today" ]];then 
	filename=`echo "$line" | awk -F " " '{print $9}'`
	mv $filename $today/
	fi
done

IFS=$oldIFS
logger -p info -t move_logs.sh "Logs movidos exitosamente al directorio de hoy $today"

