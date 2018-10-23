#!/bin/bash
for i in 1 2 3 4 5 6 7 8 9
do
	sudo rsync -xa --progress /nfs/master_raspbian/ /nfs/client10${i}_raspbian/
	sudo cp /nfs/client_config/client10${i}_raspbian/fstab /nfs/client10${i}_raspbian/etc/fstab
done

