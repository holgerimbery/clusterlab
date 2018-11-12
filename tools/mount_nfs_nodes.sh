#!/bin/sh

ansible nodes -i ../hosts --become --args "mount -t nfs 192.168.1.100:nfs/common /srv" --forks 4 --user pi
ansible nodes -i ../hosts --become -m lineinfile -a "path='/etc/fstab' line='192.168.1.100:/nfs/common /srv nfs auto,rw,rsize=8192,wsize=8192 0 0' insertbefore='EOF'" --user pi