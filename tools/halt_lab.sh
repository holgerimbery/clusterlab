#!/bin/sh

ansible clusterlab -i ../hosts --become --args "/sbin/halt" --forks 4 --user pi
