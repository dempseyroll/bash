#!/bin/bash
# Un script para automatizar los cambios de lenguajes en los ambientes.

read -p "Ingrese el nombre del ambiente en el server (ejemplos: ): " CLIENT_ENV
#read -p "Ingrese la IP de la instancia donde se encuentra el ambiente: " CLIENT_IP
read -p "Ingrese idioma a setear (Ejemplos: ): " NEW_LANG

CLIENT_IP=$(nslookup $CLIENT_ENV.domain | grep "Address: " | cut -d " " -f2)
echo -ne "Client IP es: $CLIENT_IP"
CUR_LANG=$(curl -s https://$CLIENT_ENV.domain/PATH | jq -r ".FIELD")
echo -ne "El codigo de lenguaje actual es: $CUR_LANG"
### Backup ###
FECHA=$(date +%d-%m-%Y)
sudo ssh $CLIENT_IP sudo cp /MAIN_PATH/$CLIENT_ENV/.php /MAIN_PATH/$CLIENT_ENV/BKUP"$FECHA".php
if [ $? -eq 0 ]; then
  echo "[+] Backup de realizado."
else
  echo "[!] Error al hacer backup de."
  exit 1
fi

sudo ssh $CLIENT_IP sudo cp /MAIN_PATH/$CLIENT_ENV/.json /MAIN_PATH/$CLIENT_ENV/BKUP"$FECHA".json
if [ $? -eq 0 ]; then
  echo "[+] Backup de realizado."
else
  echo "[!] Error al hacer backup."
  exit 1
fi

### Change lang ###

sudo ssh $CLIENT_IP "sudo sed -i \"s/'FIELD' => '${CUR_LANG}'/'FIELD' => '${NEW_LANG}'/g\" /MAIN_PATH/$CLIENT_ENV/.php"
if [ $? -eq 0 ]; then
  echo "[+] El del cliente $CLIENT_ENV fue modificado."
else
  echo "[!] Error al modificar."
  exit 1
fi

sudo ssh $CLIENT_IP sudo sed -i "s/${CUR_LANG}/${NEW_LANG}/g" /MAIN_PATH/$CLIENT_ENV/.json
if [ $? -eq 0 ]; then
  echo "[+] El del cliente $CLIENT_ENV fue modificado."
else
  echo "[!] Error al modificar."
  exit 1
fi

### Restart Apache ###
sudo ssh $CLIENT_IP sudo systemctl restart apache2
if [ $? -eq 0 ]; then
  echo "[+] Apache reiniciado OK."
else
  echo "[!] Error al reiniciar Apache2. Revisar logs de apache y/o SO."
  exit 1
fi

## TEST OK ###
echo -e "Prints de prueba"
echo
sudo ssh $CLIENT_IP sudo ls -lhtr /MAIN_PATH/$CLIENT_ENV/BKUP_$FECHA.php
sudo ssh $CLIENT_IP sudo ls -lhtr /MAIN_PATH/$CLIENT_ENV/BKUP_$FECHA.json
sudo ssh $CLIENT_IP sudo cat /MAIN_PATH/$CLIENT_ENV/1.php | grep "FIELD" -C2
sudo ssh $CLIENT_IP sudo cat /MAIN_PATH/$CLIENT_ENV/2.json
