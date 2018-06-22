#!/bin/bash
#
# This script will build the docker image and push it to dockerhub.
#
# Usage: buildAndPush.sh imageName
#
# Dockerhub image names look like "username/appname" and must be all lower case.

IMAGE_NAME="adamcattermole/whisk-haskell-base"

echo "Using $IMAGE_NAME as the image name"

echo "Copying Striot"
mkdir -p striot/
cp -R ../../../../license.txt striot/
cp -R ../../../../striot.cabal striot/
cp -R ../../../../src striot/

# Make the docker image
docker build -t $IMAGE_NAME .
if [ $? -ne 0 ]; then
    echo "Docker build failed"
    exit
fi
docker push $IMAGE_NAME
if [ $? -ne 0 ]; then
    echo "Docker push failed"
    exit
fi
