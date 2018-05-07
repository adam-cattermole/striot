# Run from a pre-built Haskell container
FROM haskell:8.0.1

RUN apt-get update && apt-get upgrade -y

COPY striot/striot.cabal /opt/striot/

WORKDIR /opt/striot

RUN cabal update && \
    cabal install --only-dependencies

# Install the network stack from Cabal as this isn't part of the core
#RUN cabal update && \
#    cabal install \
#    network \
#    split \
#    stm \
#    HTF \
#    aeson

COPY striot /opt/striot

#WORKDIR /opt/striot

RUN cabal update && \
    cabal build && \
    cabal install
