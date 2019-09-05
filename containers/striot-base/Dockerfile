# Run from a pre-built Haskell container
FROM haskell:8.6

RUN apt-get update && \
    apt-get upgrade -y

RUN git clone https://github.com/edenhill/librdkafka && \
    cd librdkafka && \
    ./configure --install-deps && \
    make && make install

# Copy cabal file and license
COPY striot/striot.cabal striot/LICENSE /opt/striot/

WORKDIR /opt/striot

# Install all dependencies defined in cabal file - we must install happy
# separately for HTF, as the image has a bootstrapping problem
RUN git clone --branch for-k8s-qos0 https://github.com/adam-cattermole/net-mqtt

RUN git clone https://github.com/adam-cattermole/mqtt-hs

RUN cabal v1-update && \
    cabal v1-install happy alex && \
    cabal v1-install c2hs && \
    cabal v1-install . --only-dependencies ./net-mqtt ./mqtt-hs --force-reinstalls --extra-include-dirs=/usr/local/include --extra-lib-dirs=/usr/local/lib

# Copy over source code in a separate layer, ensuring above is cached if
# cabal file does not change
COPY striot/src /opt/striot/src

RUN cabal v1-install . ./net-mqtt ./mqtt-hs

ENV LD_LIBRARY_PATH="/usr/local/lib"
