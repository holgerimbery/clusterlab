#!/bin/sh

ansible nodes -i ../hosts --become --args "/sbin/halt" --forks 4 --user pi
