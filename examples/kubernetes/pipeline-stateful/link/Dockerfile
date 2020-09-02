FROM adamcattermole/striot-base:latest
WORKDIR /opt/node
COPY . /opt/node

RUN ghc node.hs
CMD /opt/node/node
