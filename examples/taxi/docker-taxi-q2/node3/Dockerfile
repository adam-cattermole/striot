FROM striot/striot-taxi:latest
WORKDIR /opt/taxi
COPY . /opt/taxi
RUN ghc node3.hs
EXPOSE 9001
CMD /opt/taxi/node3
