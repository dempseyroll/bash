#!/bin/bash
## Execute as root ##
INCREMENT_GB=500
CMD_DF=$(df -hT / | awk -F " " '{printf $6}' | cut -d "%" -f2)
THRESHOLD="79"
SERVER_LIST=$(cat servers_list.txt)
KEY_PATH="/root/.ssh/"
DISCORD_WEBHOOK="YOUR_WEBHOOK"

discord_notify() {
    local MESSAGE="$1"
    curl -s -H "Content-Type: application/json" \
        -X POST \
        -d "{\"content\": \"$MESSAGE\"}" \
        "$DISCORD_WEBHOOK"
}
######## TEST ########

######################
for server in $SERVER_LIST; do
	SRV_IP=$(echo $server | cut -d " " -f1)
	KEY=$(echo $server | cut -d " " -f2)
	ACTUAL=$(ssh -i $KEY_PATH$KEY -o StrictHostKeyChecking=no $SRV_IP $CMD_DF)
	if [ $ACTUAL -ge $THRESHOLD ];then
		echo "THRESHOLD EXCEEDED. Starting disk resizing..."
		INSTANCE_ID=$(ssh -i $KEY_PATH$KEY -o StrictHostKeyChecking=no $SRV_IP sudo curl -s http://169.254.169.254/latest/meta-data/instance-id)
		REGION=$(ssh -i $KEY_PATH$KEY -o StrictHostKeyChecking=no $SRV_IP sudo curl -s http://169.254.169.254/latest/meta-data/placement/region)
		ROOT_DEV=$(ssh -i $KEY_PATH$KEY -o StrictHostKeyChecking=no $SRV_IP "findmnt -n -o SOURCE /")
		if [[ "$ROOT_DEV" == "/dev/root" ]]; then
			ROOT_DEV=$(ssh -i $KEY_PATH$KEY -o StrictHostKeyChecking=no $SRV_IP "readlink -f /dev/root")
		fi
		# Device base (xvda o nvme0n1)
		DEVICE_NAME=$(ssh -i $KEY_PATH$KEY -o StrictHostKeyChecking=no $SRV_IP "lsblk -no PKNAME $ROOT_DEV")
		# Asegurar formato /dev/xvda o /dev/nvme0n1
		# Obtener ID del volumen donde está montado el /
		VOLUME_ID=$(ssh -i "$KEY" -o StrictHostKeyChecking=no ec2-user@$IP \
			"ls -l /dev/disk/by-id/ | grep nvme-Amazon_Elastic_Block_Store | grep $DEVICE_NAME | sed -E 's/.*Elastic_Block_Store_(vol[^ ]+).*/\1/'")
		# Extraer el Volume ID limpio y darle formato correcto con guión
		RAW_VOLUME_ID=$(echo "$VOLUME_ID" | grep -o 'vol[0-9a-zA-Z]*' | grep -v part | head -n1)
		VOLUME_ID_FORMATTED=$(echo "$RAW_VOLUME_ID" | sed 's/^vol/vol-/')
		echo "[+] Volumen raíz: $VOLUME_ID_FORMATTED"
		logger "[EBS-AUTOSCALER] [+] Volumen raíz: $VOLUME_ID_FORMATTED"
		CURRENT_SIZE=$(aws ec2 describe-volumes \
			--volume-ids "$VOLUME_ID_FORMATTED" \
			--region "$REGION" \
			--query "Volumes[0].Size" \
			--output text)
		NEW_SIZE=$($CURRENT_SIZE + $INCREMENT_GB)
		# Discord notification #
		discord_notify ":warning: [AutoScaler] El servidor $SRV_IP está usando $ACTUAL% de disco. Iniciando snapshot y resize a ${NEW_SIZE}GiB..."
		logger "[EBS-AUTOSCALER] El servidor $SRV_IP está usando $ACTUAL% de disco. Iniciando snapshot y resize a ${NEW_SIZE}GiB... "
		# START FIXING TASKS #
		# Snapshot
		echo "[+] Creando snapshot: $SNAPSHOT_ID"
		logger "[EBS-AUTOSCALER] [+] Creando snapshot: $SNAPSHOT_ID"
		SNAPSHOT_NAME="${SRV_IP}_$(date +%Y%m%d_%H%M%S)"
		SNAPSHOT_ID=$(aws ec2 create-snapshot \
			--volume-id "$VOLUME_ID_FORMATTED" \
			--description "Backup before autoscale $SNAPSHOT_NAME" \
			--region "$REGION" \
			--tag-specifications "ResourceType=snapshot,Tags=[{Key=Name,Value=$SNAPSHOT_NAME}]" \
			--query SnapshotId --output text)
		# Resize disk
		echo "[+] Aumentando volumen a ${NEW_SIZE}GiB..."
		logger "[EBS-AUTOSCALER] Aumentando volumen a ${NEW_SIZE}GiB..."
		aws ec2 modify-volume \
			--volume-id "$VOLUME_ID_FORMATTED" \
			--size "$NEW_SIZE" \
			--region "$REGION"
		echo "[+] Esperando unos segundos para asegurar disponibilidad del nuevo tamaño..."
		logger "[EBS-AUTOSCALER] Esperando unos segundos para asegurar disponibilidad del nuevo tamaño..."
		sleep 10
		# Refresh Filesystem in the server
		echo "[+] Ejecutando expansión de partición y filesystem..."
		logger "[EBS-AUTOSCALER] Ejecutando expansión de partición y filesystem..."
		ssh $SRV_IP -i $KEY_PATH$KEY << 'EOF'
			sudo set -e
			echo "[+] Detectando partición montada en '/'..."
			ROOT_PART=$(sudo findmnt -n -o SOURCE /)

			# Si es un symlink como /dev/root, resolvemos el enlace
			if [[ "$ROOT_PART" == "/dev/root" ]]; then
    				ROOT_PART=$(readlink -f "$ROOT_PART")
			fi

			# Detectamos el disco base (sin número de partición)
			DEVICE=$(sudo lsblk -no PKNAME "$ROOT_PART")
			DEVICE="/dev/$DEVICE"

			# Detectamos el número de partición desde la raíz (si aplica)
			PARTNUM=$(echo "$ROOT_PART" | grep -o '[0-9]*$')

            		echo "[+] Dispositivo base: $DEVICE, Partición #: $PARTNUM"

            		echo "[+] Expandiendo partición..."
            		sudo growpart "$DEVICE" "$PARTNUM"

            		echo "[+] Detectando tipo de filesystem..."
            		FSTYPE=$(df -T / | awk 'NR==2 {print $2}')
            		echo "[+] Filesystem: $FSTYPE"

            		if [[ "$FSTYPE" == "xfs" ]]; then
                		sudo xfs_growfs /
            		else
                		sudo resize2fs "$ROOT_PART"
            		fi

            		echo "[+] ¡Expansión completada exitosamente!"
EOF
		# Send notification to Discord:
		discord_notify ":white_check_mark: [AutoScaler] El servidor $SRV_IP ha sido expandido correctamente. Nuevo tamaño: ${NEW_SIZE}GiB."
	else
		echo "[INFO] No hay problemas con ningún disco."
		logger "[EBS-AUTOSCALER] No hay problemas con ningún disco."
		exit 0
	fi
done;
