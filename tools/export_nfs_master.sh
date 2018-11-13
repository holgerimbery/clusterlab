#!/bin/sh
ansible master -i ../hosts --become --args "mkdir /nfs/common" --user pi
#ansible master -i ../hosts --become -m lineinfile -a "path='/etc/exports' line='/nfs *(rw,sync,no_subtree_check,no_root_squash)' insertbefore='EOF'" --user pi
ansible master -i ../hosts --become --args "exportfs -ra" --user pi
