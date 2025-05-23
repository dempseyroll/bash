#!/bin/bash
# Please give permissions before: chmod u+x docker_group_add.sh
# Then run.
sudo groupadd docker
sudo usermod -aG docker $USER
newgrp docker
