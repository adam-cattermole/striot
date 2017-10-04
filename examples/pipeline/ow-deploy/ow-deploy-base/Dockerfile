# Dockerfile for example whisk docker action
FROM openwhisk/dockerskeleton

ENV FLASK_PROXY_PORT 8080

### Add source file(s) and project config cabal
# ADD requirements.txt /action/requirements.txt

### Install all required dependencies and update them
RUN echo http://dl-cdn.alpinelinux.org/alpine/edge/main >> /etc/apk/repositories \
  && echo http://dl-cdn.alpinelinux.org/alpine/edge/community >> /etc/apk/repositories \
  && apk upgrade --update-cache --available \
  && apk add --no-cache --virtual .build-deps \
  musl-dev \
  linux-headers \
  zlib-dev \
  gcc \
  ghc \
  cabal \
  && cabal update


### Install project specific Haskell dependencies and compile source file(s)
# RUN cd /action; \
#   cabal update && cabal install $(cat requirements.txt)

# Copy these first
COPY striot/striot.cabal /opt/striot/
COPY striot/license.txt /opt/striot/

WORKDIR /opt/striot

RUN cabal update && \
    cabal install --only-dependencies

# We copy the src after so that source code changes do not require
# re-installation of dependencies. That only happens if we change the license or
# cabal file
COPY striot/src /opt/striot/src

# For caching reasons
RUN cabal update && \
    cabal build && cabal install

WORKDIR /
