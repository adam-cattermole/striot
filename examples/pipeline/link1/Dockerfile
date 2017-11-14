#Run from a pre-built Haskell container
FROM jmtd/striot-base:latest

WORKDIR /opt/link1


# Add and Install Application Code
COPY . /opt/link1

# Compile
RUN ghc Link1.hs

# Run the client
CMD ["/opt/link1/Link1"]
