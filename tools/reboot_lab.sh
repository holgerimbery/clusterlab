#!/bin/sh

ansible nodes -i ../hosts --become --args "/sbin/reboot" --background 30 --forks 4 --user pi
