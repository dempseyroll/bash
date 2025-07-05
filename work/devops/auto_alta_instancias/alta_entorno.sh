#!/bin/bash
# * Automate Alta de instancias * # PODER LANZAR DESDE BASTION
### Credenciales de BBDD propias, limpiar al final ###
#################### VARS ####################
set -a
source .env
set +a
set +H # Desactivar history expansion, para evitar errores con passwords con "!"

read -sp "Ingresa tu pass de MYSQL de la DB del cliente (No se almacenará): " MYSQL_PASS
echo
read -p "Ingrese el nombre del entorno del cliente (Ej: ): " CLIENT_ENV
read -sp "Ingrese la password para la Base de Datos del cliente (solo se almacenará en las config que correspondan): " CLIENT_PASS_DB
echo
read -p "Ingrese el host de Base de datos correspondiente al entorno: " CLIENT_HOST_DB
read -sp "Ingrese tu pass del Maestro DB Config Business (No se almacenará): " MASTER_PASS
echo
read -p "Ingrese el idioma a configurar (Ejemplo: ) : " LANGU
read -p "Ingrese el string de entorno para DB (Ejemplo: testing, prod, uat): " ENVI
#read -p "Ingrese la IP pública del ambiente: " CLIENT_IP
read -p "Ingrese la key a utilizar para el deploy (Ejemplo: .PEM): " CLIENT_KEY
#read -p "Ingrese el nombre del dir donde se obtendrán las imagenes (Ej:): " IMG_SRC
read -p "Ingrese la versión (Ej: ): " TAG
CLIENT_IP=$(nslookup $CLIENT_ENV.domain | grep "Address: " | cut -d " " -f2)
CLIENT_USER_DB="usr_"$CLIENT_ENV # usr_ + entorno del client.
# FIRST FOR OWN MYSQL PASSWORD.
MYSQL_PWD=$MYSQL_PASS
####################################################################################################################################
################################################## [+] STAGE 0: create DNS record ##################################################
sudo sed -e "s/ENTORNO/${CLIENT_ENV}/g" -e "s/CLIENT_IP/${CLIENT_IP}/g" temp_change-batch.json > work/change-batch.json
if [ $? -eq 0 ]; then
  echo "[+] Json para agregar registro a Route 53 construido exitosamente."
else
  echo "[!] Error al construir archivo json para Route 53. Revisar si ya existe el dominio."
  exit 1
fi

JSON_FILE="work/change-batch.json"
aws route53 change-resource-record-sets --hosted-zone-id ZONE_ID --change-batch file://$JSON_FILE # La hosted zone es únicamente la de.
if [ $? -eq 0 ]; then
  echo "[+] Json para agregar registro a Route 53 construido exitosamente."
else
  echo "[!] Error al construir archivo json para Route 53. Revisar si ya existe el dominio."
  exit 1
fi

################################################### [+] STAGE 1: Database schema, user and grants ###################################################
######## NEW VERSION ########
cat > work/client.sql <<EOF
CREATE USER IF NOT EXISTS '$CLIENT_USER_DB'@'%' IDENTIFIED BY '${CLIENT_PASS_DB}';
CREATE DATABASE IF NOT EXISTS \`$CLIENT_ENV\`;
GRANT ALL PRIVILEGES ON \`$CLIENT_ENV\`.* TO '$CLIENT_USER_DB'@'%';
EOF

sudo --preserve-env=MYSQL_PWD mysql -h $CLIENT_HOST_DB -u $MYSQL_USER < work/client.sql
if [ $? -eq 0 ]; then
  echo "[+] Alta de usuario, DB y grants OK."
else
  echo "[!] Error en el alta por DB de '$CLIENT_ENV'. Posible error de sintáxis y/o autenticación."
  exit 1
fi

#################################### CONFIG BUSINESS - MAESTRO #####################################
#### NEW VERSION ######
MYSQL_PWD=$MASTER_PASS
cat > work/master.sql <<EOF
INSERT INTO \`SCHEMA\`.\`TABLE\` (id, descripcion) VALUES (NULL, '$CLIENT_ENV');
INSERT INTO \`SCHEMA\`.\`TABLE\` (FIELDS) VALUES ((SELECT id from SCHEMA.TABLE where descripcion = '$CLIENT_ENV'), (SELECT id from SCHEMA.TABLE where descripcion = '$CLIENT_ENV'), 'https://$CLIENT_ENV.domain/PATH', 'https://$CLIENT_ENV.domain/PATH', '$ENVI', CONCAT(LOWER((select id from \`SCHEMA\`.\`TABLE\` where descripcion = '$CLIENT_ENV')),'000'));
INSERT INTO \`SCHEMA\`.\`TABLE\` select NULL as id, (select id from \`SCHEMA\`.\`TABLE\` where descripcion = '$CLIENT_ENV') as ALIASES from \`SCHEMA\`.\`TABLE\` where FIELD in (SELECT id FROM SCHEMA.TABLE where STR_FIELD = 'DEFAULT');
EOF

sudo --preserve-env=MYSQL_PWD mysql -h $MASTER_HOST -u $MASTER_USER < work/master.sql
if [ $? -eq 0 ]; then
  echo "[+] Alta en DB realizada correctamente."
else
  echo "[!] Error al insertar en . Revisar sintáxis."
  exit 1
fi
#### END NEW VERSION #####

############################################ [+] STAGE 2: Servidor APP #########################################################
# Crear directorios #
sudo ssh $CLIENT_IP sudo mkdir -p /MAIN_PATH/$CLIENT_ENV/{NEW_SUBPATHS}
if [ $? -eq 0 ]; then
  echo "[+] Estructura de directorios /MAIN_PATH/$CLIENT_ENV/{NEW_SUBPATHS} creada exitosamente."
else
  echo "[!] Error al crear estructura de dirs /MAIN_PATH/$CLIENT_ENV/{NEW_SUBPATHS}."
  exit 1
fi

sudo ssh $CLIENT_IP sudo mkdir -p /MAIN_PATH/$CLIENT_ENV/{NEW_OTHER_SUBPATHS}
if [ $? -eq 0 ]; then
  echo "[+] Estructura de directorios /MAIN_PATH/$CLIENT_ENV/{NEW_OTHER_SUBPATHS} creada exitosamente."
else
  echo "[!] Error al crear estructura de dirs /MAIN_PATH/$CLIENT_ENV/{NEW_OTHER_SUBPATHS}."
  exit 1
fi

sudo ssh $CLIENT_IP sudo chown www-data:www-data /MAIN_PATH/$CLIENT_ENV/{NEW_OTHER_SUBPATHS}
if [ $? -eq 0 ]; then
  echo "[+] Ownership otorgado exitosamente."
else
  echo "[!] Error al otorgar ownership a los dirs."
  exit 1
fi

######################### Apache initial config ###############################
# Generate clean apache initial config file from template #
sudo sed -e "s/ENTORNO/${CLIENT_ENV}/g" temp_apache_init.conf >> work/$CLIENT_ENV.domain
if [ $? -eq 0 ]; then
  echo "[+] Archivo inicial .conf de Apache construido correctamente."
else
  echo "[!] Error al intentar construir archivo .conf de Apache."
  exit 1
fi

# Upload file to directory
sudo scp work/$CLIENT_ENV.domain $CLIENT_IP:~
if [ $? -eq 0 ]; then
  echo "[+] Archivo inicial .conf de Apache subido correctamente a $CLIENT_IP"
else
  echo "[!] Error al subir archivo de config de Apache."
  exit 1
fi

sudo ssh $CLIENT_IP sudo mv $CLIENT_ENV.domain /etc/apache2/sites-enabled/ 
sudo ssh $CLIENT_IP sudo chmod 644 /etc/apache2/sites-enabled/$CLIENT_ENV.domain.conf
sudo ssh $CLIENT_IP sudo chown root:root /etc/apache2/sites-enabled/$CLIENT_ENV.domain.conf

# Check syntax #
sudo ssh $CLIENT_IP sudo apache2ctl -t
if [ $? -eq 0 ]; then
  echo "[+] Test de sintaxis de Apache OK."
else
  echo "[!] Error de sintaxis en configuracion de Apache."
  exit 1
fi

# Restart Apache2 #
sudo ssh $CLIENT_IP sudo systemctl restart apache2.service
if [ $? -eq 0 ]; then
  echo "[+] Apache2 reiniciado correctamente."
else
  echo "[!] Error al querer reiniciar apache2."
  exit 1
fi
################################ Certs SSL ####################################
# Crear certificados SSL #
sudo ssh $CLIENT_IP sudo certbot certonly --apache -d $CLIENT_ENV.domain --dry-run --non-interactive --agree-tos --email it@domain
if [ $? -eq 0 ]; then
  echo "[+] Dry-run corrido correctamente."
else
  echo "[!] Error al correr dry-run."
  exit 1
fi

# Generar certificados #
sudo ssh $CLIENT_IP sudo certbot certonly --apache -d $CLIENT_ENV.domain --non-interactive --agree-tos --email it@domain
if [ $? -eq 0 ]; then
  echo "[+] Certificados TLS generados correctamente."
else
  echo "[!] Error al generar certificados TLS."
  exit 1
fi

################################ APACHE FINAL CONFIG ################################
# Generate clean apache FINAL config file from template #
sudo sed -e "s/ENTORNO/${CLIENT_ENV}/g" temp_apache_final.conf > work/$CLIENT_ENV.domain.conf
if [ $? -eq 0 ]; then
  echo "[+] Archivo FINAL .conf de Apache construido correctamente."
else
  echo "[!] Error al intentar construir archivo FINAL .conf de Apache."
  exit 1
fi

# Upload file to directory
sudo scp work/$CLIENT_ENV.domain.conf $CLIENT_IP:~
if [ $? -eq 0 ]; then
  echo "[+] Archivo FINAL .conf de Apache subido correctamente a $CLIENT_IP"
else
  echo "[!] Error al subir archivo de config FINAL de Apache."
  exit 1
fi

sudo ssh $CLIENT_IP sudo mv $CLIENT_ENV.domain.conf /etc/apache2/sites-enabled/ 
sudo ssh $CLIENT_IP sudo chmod 644 /etc/apache2/sites-enabled/$CLIENT_ENV.domain.conf
sudo ssh $CLIENT_IP sudo chown root:root /etc/apache2/sites-enabled/$CLIENT_ENV.domain.conf

# Check syntax #
sudo ssh $CLIENT_IP sudo apache2ctl -t
if [ $? -eq 0 ]; then
  echo "[+] Test de sintaxis de Apache OK."
else
  echo "[!] Error de sintaxis en configuracion de Apache."
  exit 1
fi

# Restart Apache2 #
sudo ssh $CLIENT_IP sudo systemctl restart apache2.service
if [ $? -eq 0 ]; then
  echo "[+] Apache2 reiniciado correctamente."
else
  echo "[!] Error al querer reiniciar apache2."
  exit 1
fi
################################################################################################################################
############################## FILE.php ##############################
# Build FILE.php #
ESCAPED_PASSWORD=$(printf '%s' "$CLIENT_PASS_DB" | sed -e 's/[\/&]/\\&/g' -e 's/\\/\\\\/g')
sudo sed -e "s/ENTORNO/${CLIENT_ENV}/g" -e "s/DB-HOST/${CLIENT_HOST_DB}/g" -e "s/DB-NAME/${CLIENT_ENV}/g" -e "s/DB-USER/${CLIENT_USER_DB}/g" -e "s/DB-PASS/${ESCAPED_PASSWORD}/g" -e "s/MASTER-HOST/${MASTER_HOST}/g" -e "s/MASTER-USER/${USR_MASTER}/g" -e "s/MASTER-PASS/${PASS_MASTER}/g" -e "s/LANGU/${LANGU}/g" temp_FILE.php > work/FILE.php
if [ $? -eq 0 ]; then
  echo "[+] FILE.php construido correctamente."
else
  echo "[!] Error al construir FILE.php desde template."
  exit 1
fi

# Upload file to directory
sudo scp work/FILE.php $CLIENT_IP:~
if [ $? -eq 0 ]; then
  echo "[+] Archivo FILE.php subido correctamente a $CLIENT_IP"
else
  echo "[!] Error al subir archivo FILE.php."
  exit 1
fi

sudo ssh $CLIENT_IP sudo mv FILE.php /MAIN_PATH/$CLIENT_ENV/SUBPATH/
sudo ssh $CLIENT_IP sudo chmod 775 /MAIN_PATH/$CLIENT_ENV/SUBPATH/FILE.php
sudo ssh $CLIENT_IP sudo chown root:root /MAIN_PATH/$CLIENT_ENV/SUBPATH/FILE.php

############################## FILE.json ##############################
### Configurar FILE.json en base a template ###
# Crear FILE.json #
sudo sed -e "s/ENTORNO/${CLIENT_ENV}/g" -e "s/LANGU/${LANGU}/g" temp_FILE.json > work/FILE.json
if [ $? -eq 0 ]; then
  echo "[+] FILE.json construido OK."
else
  echo "[!] Error al construir FILE.json."
  exit 1
fi

# Upload file to directory
sudo scp work/FILE.json $CLIENT_IP:~
if [ $? -eq 0 ]; then
  echo "[+] Archivo FILE.json subido correctamente a $CLIENT_IP"
else
  echo "[!] Error al subir archivo FILE.json."
  exit 1
fi

sudo ssh $CLIENT_IP sudo mv FILE.json /MAIN_PATH/$CLIENT_ENV/SUBPATH/
sudo ssh $CLIENT_IP sudo chmod 644 /MAIN_PATH/$CLIENT_ENV/SUBPATH/FILE.json
sudo ssh $CLIENT_IP sudo chown root:root /MAIN_PATH/$CLIENT_ENV/SUBPATH/FILE.json

###################################################################################################################################################
###################### Imagenes pre-deploy inicial ######################
sudo mkdir /DEPLOY/images/$CLIENT_ENV
if [ $? -eq 0 ]; then
  echo "[+] Directorio de imagenes creado correctamente."
else
  echo "[!] Error al crear directorio de imagenes para $CLIENT_ENV"
  exit 1
fi

### REVISAR CASO! ###
ls /DEPLOY/images/*$CLIENT_ENV*
if [ $? -eq 0 ]; then
  IMG_SRC=$(ls -lhtr /DEPLOY/images/*CLIENT-* | grep "opt" | cut -d "/" -f7 | cut -d ":" -f1 | tail -1) # DEFAULT
  sudo cp /DEPLOY/images/$IMG_SRC/* /DEPLOY/images/$CLIENT_ENV/
else
  # ES UN CLIENTE NUEVO, dejar imgs antes en /HOME/ALTA/work:
  echo -ne "Cliente nuevo, se moverán las imagenes al dir creado antes."
  sudo cp /HOME/ALTA/work/logo-* /DEPLOY/images/$CLIENT_ENV
fi
#### TAL VEZ CAMBIE ESTE FLUJO SI EL CLIENTE ES COMPLETAMENTE NUEVO ###
# Copy imagenes desde otro ambiente del mismo cliente (si existe).
#sudo cp /DEPLOY/images/$IMG_SRC/* /DEPLOY/images/$CLIENT_ENV/ ### ESTE BLOQUE SE VA SI FUNCA LO DEL IF ANTERIOR!

################################################# [+] STAGE 3: Dump inicial #################################################
# Subir dump inicial. Ubicado en "/DEPLOY/ORG_PATH" del server pivot. Utilizar dump + reciente. #
# comando para obtener último template/dump actualizado:
LAST_BKUP=$(ls -lhtr /DEPLOY/ORG_PATH/ | grep "PATTERN" | awk -F " " '{printf $9}')
# FOR ENTER WITH CLIENT USER:
MYSQL_PWD=$CLIENT_PASS_DB
sudo --preserve-env=MYSQL_PWD mysql -f -h $CLIENT_HOST_DB -u $CLIENT_USER_DB $CLIENT_ENV < /DEPLOY/ORG_PATH/$LAST_BKUP
if [ $? -eq 0 ]; then
  echo "[+] Dump inicial de DB cargado exitosamente."
else
  echo "[!] Error al cargar dump inicial de DB."
  exit 1
fi

################################################## [+] STAGE 4: Deploy inicial ##################################################
# Deploy última versión, en dir "/DEPLOY/ORG" server pivot. #
# Igualar Metadatos Repo Local vs Github #
cd /DEPLOY/ORG/ && sudo git fetch --force 
if [ $? -eq 0 ]; then
  echo "[+] Git Fetch ejecutado correctamente"
else
  echo "[!] Error al ejecutar git fetch."
  exit 1
fi

sudo git status && sudo git checkout $TAG
if [ $? -eq 0 ]; then
  echo "[+] Checkout a la versión $TAG ejecutado correctamente."
else
  echo "[!] Error al ejecutar git checkout."
  exit 1
fi

cd /DEPLOY/
sudo sh SCRIPT.sh $CLIENT_ENV $CLIENT_KEY $CLIENT_IP #
cd /HOME/ALTA
######################################### FIX DEPLOY INICIAL #########################################
sudo --preserve-env=MYSQL_PWD mysql -h $CLIENT_HOST_DB -u $CLIENT_USER_DB -e "INSERT INTO \`$CLIENT_ENV\`.\`TABLE\` (FIELDS) VALUES (VALUES_INSERT);"
if [ $? -eq 0 ]; then
  echo "[+] Insert del Fix Deploy Inicial ejecutado correctamente."
else
  echo "[!] Error al insertar registro en la DB para el Fix Deploy Inicial."
  exit 1

############################ Ejecución de Fix Deploy Inicial #####################################
sudo ssh $CLIENT_IP "cd /MAIN_PATH/$CLIENT_ENV/SUBPATH && sudo BIN mig -c CONF/1.php"
echo "[+] Ejecutado Fix de Deploy inicial."

################################################## [+] STAGE 5: Generar config business local & Fix permisos cron ##################################################
# Obtener Token #
sudo curl -d '{"username":"USER","password":"PASS"}' -H "Content-Type: application/json" -H "Accept: application/json" -X POST https://$CLIENT_ENV.domain/get_token > work/Token.txt
if [ $? -eq 0 ]; then
  echo "[+] Token obtenido correctamente en el archivo Token.txt"
else
  echo "[!] Error al obtener token."
  exit 1
fi

TOKEN=$(sudo cat work/Token.txt | jq -r .token)
sudo curl -X POST -H "Content-Type: application/json" -H "Authorization-Token: $TOKEN" https://$CLIENT_ENV.domain/ENDPOINT
if [ $? -eq 0 ]; then
  echo "[+] Get realizado correctamente."
else
  echo "[!] Error al realizar Get."
  exit 1
fi

# Generar cliente, entorno y Flows #
# COMING SOON #
rm -f work/FILE.php work/FILE.json work/$CLIENT_ENV.domain.conf work/Token.txt work/change-batch.json work/client.sql work/master.sql work/logo-*
unset MYSQL_PWD
unset TOKEN
set -H
