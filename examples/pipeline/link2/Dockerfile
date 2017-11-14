#Run from a pre-built Haskell container
FROM sjwoodman/striot-base:latest

WORKDIR /opt/link2


# Add and Install Application Code
COPY . /opt/link2

# Compile
RUN ghc Link2.hs

# Run the client
CMD ["/opt/link2/Link2"]
