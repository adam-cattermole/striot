#Run from a pre-built Haskell container
FROM sjwoodman/striot-base:latest

WORKDIR /opt/link3


# Add and Install Application Code
COPY . /opt/link3

# Compile
RUN ghc Link3.hs

# Run the client
CMD ["/opt/link3/Link3"]
