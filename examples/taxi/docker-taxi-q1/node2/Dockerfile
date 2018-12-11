FROM striot/striot-taxi:latest
WORKDIR /opt/taxi
COPY . /opt/taxi
RUN ghc node2.hs
CMD /opt/taxi/node2
