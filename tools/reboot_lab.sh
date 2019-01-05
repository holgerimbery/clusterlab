#!/bin/sh

ansible nodes -i ../inventory --become --args "/sbin/reboot" --background 30 --forks 4 --user pi
