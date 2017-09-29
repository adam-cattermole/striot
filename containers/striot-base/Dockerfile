# Run from a pre-built Haskell container
FROM haskell:8.0.1

RUN apt-get update && apt-get upgrade -y

# Install the network stack from Cabal as this isn't part of the core
# RUN cabal update && \
#     cabal install network split stm mqtt-hs aeson string-conversions

# COPY striot /opt/striot
# COPY whisk-rest /opt/whisk-rest
# install extras for whisk-rest
# RUN cabal install wreq

# build sub-module whisk-rest
# COPY whisk-rest /opt/whisk-rest
# WORKDIR /opt/whisk-rest
# RUN cabal update && \
#   cabal build && cabal install

COPY striot /opt/striot
WORKDIR /opt/striot

RUN cabal update && \
  cabal install --only-dependencies

# Separate for caching
RUN cabal update && \
  cabal build && cabal install
