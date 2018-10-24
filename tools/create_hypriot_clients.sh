#!/bin/bash
for i in 1 2 3 4 5 6 7 8 9
do
	sudo rsync -xa --progress /nfs/master_hypriot/ /nfs/client10${i}_hypriot/
	sudo cp /nfs/client_config/client10${i}_hypriot/fstab /nfs/client10${i}_hypriot/etc/fstab
	sudo cp /nfs/client_config/client10${i}_hypriot/user-data /nfs/client10${i}_hypriot/var/lib/cloud/seed/nocloud-net/user-data
	sudo cp /nfs/client_config/client10${i}_hypriot/meta-data /nfs/client10${i}_hypriot/var/lib/cloud/seed/nocloud-net/meta-data
done

