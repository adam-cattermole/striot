FROM adamcattermole/striot-base-arm:8.8.1-large
WORKDIR /opt/node
COPY . /opt/node

RUN ghc node.hs
EXPOSE 9001
CMD /opt/node/node
