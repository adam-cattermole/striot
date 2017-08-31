# Dockerfile for example whisk docker action
FROM adamcattermole/whisk-haskell-base

ENV FLASK_PROXY_PORT 8080

### Add source file(s) and project config cabal
ADD function.hs /action/function.hs
ADD whisk-haskell-base.cabal /action/whisk-haskell-base.cabal


#### TODO: Do we need this? Surely if it's done in the base image we likely don't?
# ## Install all required dependencies and update them
# RUN echo http://dl-cdn.alpinelinux.org/alpine/edge/main >> /etc/apk/repositories \
#   && echo http://dl-cdn.alpinelinux.org/alpine/edge/community >> /etc/apk/repositories \
#   && apk upgrade --update-cache --available \
#   && apk add --no-cache --virtual .build-deps \
#   musl-dev \
#   gcc \
#   ghc \
#   cabal \
#   && cabal update


### Install project specific Haskell dependencies and compile source file(s)
RUN cd /action; cabal install \
  && ghc -o exec function.hs
  # && apk del .build-deps

CMD ["/bin/bash", "-c", "cd actionProxy && python -u actionproxy.py"]
