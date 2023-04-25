#!/bin/bash
myDir=$(dirname $(realpath "$0"))
myName=$(basename "$0")
pushd $myDir
docker build -f Dockerfile -t overlay-system .
popd
