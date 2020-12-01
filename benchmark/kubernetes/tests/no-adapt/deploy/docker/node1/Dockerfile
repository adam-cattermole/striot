FROM striot/striot-base:latest
WORKDIR /opt/node
COPY . /opt/node
RUN mkdir /opt/node/data

RUN ghc node.hs
CMD /opt/node/node
