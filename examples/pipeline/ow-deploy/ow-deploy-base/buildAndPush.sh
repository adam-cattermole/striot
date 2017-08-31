#!/bin/bash
#
# This script will build the docker image and push it to dockerhub.
#
# Usage: buildAndPush.sh imageName
#
# Dockerhub image names look like "username/appname" and must be all lower case.

IMAGE_NAME="adamcattermole/whisk-haskell-base"

echo "Using $IMAGE_NAME as the image name"

echo "Copying whisk-rest"
mkdir -p whisk-rest/
cp -R ../../../../src/whisk-rest/LICENSE whisk-rest/
cp -R ../../../../src/whisk-rest/whisk-rest.cabal whisk-rest/
cp -R ../../../../src/whisk-rest/src whisk-rest/

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
