#!/bin/bash

prefix=${prefix-sjwoodman}

echo "Copying Striot"
mkdir -p striot-base/striot/src
cp -R ../license.txt striot-base/striot/
cp -R ../striot.cabal striot-base/striot/
cp -R ../src/* striot-base/striot/src

# echo "Copying whisk-rest"
# mkdir -p striot-base/whisk-rest/
# cp -R ../src/whisk-rest/LICENSE striot-base/whisk-rest/
# cp -R ../src/whisk-rest/whisk-rest.cabal striot-base/whisk-rest/
# cp -R ../src/whisk-rest/src striot-base/whisk-rest/

echo "Building"
docker build -t $prefix/striot-base striot-base
