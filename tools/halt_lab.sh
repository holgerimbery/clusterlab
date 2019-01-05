#!/bin/sh

ansible nodes -i ../inventory --become --args "/sbin/halt" --forks 4 --user pi
