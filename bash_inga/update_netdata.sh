#!/usr/bin/env bash
#
# lazy sysadmin is lazy
# =========================================================

echo -e '>>> Entering NetData source directory...'
cd /root/recipes/netdata

echo -e '>>> Pulling Latest Version...'
git pull origin master

echo -e '>>> Compiling to /opt/netdata ...'
./netdata-installer.sh --install /opt
