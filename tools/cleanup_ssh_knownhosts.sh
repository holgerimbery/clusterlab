#!/bin/sh

for i in 1 2 3 4 5 6 7 8 9
do
  echo "Cleaning up 192.168.1.10${i}"
  ssh-keygen -R 192.168.1.10${i}
  ssh-keyscan -H 192.168.1.10${i} >> ~/.ssh/known_hosts
done
