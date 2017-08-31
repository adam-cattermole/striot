# Dockerfile for example whisk docker action
FROM openwhisk/dockerskeleton

ENV FLASK_PROXY_PORT 8080

### Add source file(s) and project config cabal
ADD requirements.txt /action/requirements.txt

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
RUN cd /action; cabal install $(cat requirements.txt)

### Install the whisk-rest library
COPY whisk-rest /opt/whisk-rest
WORKDIR /opt/whisk-rest
RUN cabal build && cabal install
WORKDIR /
