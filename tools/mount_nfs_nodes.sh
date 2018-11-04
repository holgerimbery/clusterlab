#!/bin/sh

ansible nodes -i ../hosts --become --args "mount -t nfs 192.168.1.100:nfs/common /srv" --forks 4 --user pi
