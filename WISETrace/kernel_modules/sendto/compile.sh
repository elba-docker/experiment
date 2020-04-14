#!/bin/bash
 
TABLE=$(grep sys_call_table /boot/System.map-$(uname -r) | head -1 | awk '{print $1}')
echo $TABLE
sed -i s/TABLE/$TABLE/g spec_sendto.c

make
