#!/bin/bash
# Colores:
RED="\033[31m"; GREEN="\033[1;32m"; YELLOW="\033[1;33m"; ENDCOLOR="\033[0m"
# Vistazo al filesystem previo a la limpieza:
df -hT

# Limpieza
echo -e $YELLOW"####################################"
echo -e $YELLOW"###### Comenzando limpieza... ######"
echo -e $YELLOW"####################################"$ENDCOLOR

sudo apt-get update -y && sudo apt-get upgrade -y &&  sudo apt-get dist-upgrade -y && sudo apt-get autoremove -y
# Ver cache previo a la limpieza de caché:
sudo du -sh /var/cache/apt/archives

# El siguiente comando elimninará ficheros en las sigs rutas: /var/cache/apt/archives/partial/*, /var/lib/apt/lists/partial/*
# /var/cache/apt/pkgcache.bin, /var/cache/apt/srcpkgcache.bin
sudo apt-get -s clean -y
sudo apt-get -s autoclean -y
sudo rm -rf /var/cache/apt/archives/*

# Control de la caché luego de la limpieza:
sudo du -sh /var/cache/apt/archives

# Clean logs of systemd:
sudo journalctl --vacuum-time=10d # You can change time to your needs.

# Delete old versions of snap apps:
set -eu
sudo snap list-all | awk ‘/disabled/{print $1, $3}’ |
	while read snapname revision; do
		sudo snap remove “$snapname” --revision=”$revision”
	done

# Delete cache of thumbnails:
sudo rm -rf ~/.cache/thumbnails/*

# Con el siguiente comando se borran automáticamente archivos del/de los kernel más antiguos:
sudo apt autoremove --purge -y

# Liberar memoria borrando caché: REVIEW IF WORKS
# sudo su
#sync && echo 1 > /proc/sys/vm/drop_caches
 # exit

# --- Check filesystem storage after all tasks ---
df -hT

echo -e $GREEN"Finished!"$ENDCOLOR

