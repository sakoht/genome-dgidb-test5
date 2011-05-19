#!/bin/bash

# This will mount VBox shared folders.
# It assumes the following names have been added to VBox:
#   gscmnt
#   var
#   lsf

if [ "$UID" -ne "0" ]
then
  echo "You must be root."
  exit 1
fi

if [ ! -d "/gscmnt" ]
then
  mkdir /gscmnt
fi
mount -t vboxsf gscmnt /gscmnt -o uid=1000,gid=100,umask=007

if [ ! -d "/gsc/var" ]
then
  mkdir -p /gsc/var
fi
mount -t vboxsf var /gsc/var -o uid=1000,gid=100,umask=007

if [ ! -d "/usr/local/lsf" ]
then
  mkdir -p /usr/local/lsf
fi
mount -t vboxsf lsf /usr/local/lsf -o uid=1000,gid=100,umask=007

if [ ! -d "/gsc/scripts" ]
then
  mkdir -p /gsc/scripts
fi
mount -t vboxsf scripts /gsc/scripts -o uid=1000,gid=100,umask=007
