#Run from a pre-built Haskell container
FROM python:3.5.4-jessie

RUN apt-get update && \
    apt-get install -y \
    autoconf \
    automake \
    libtool \
    bison \
    flex

RUN git clone https://github.com/satori-com/tcpkali.git

WORKDIR tcpkali

RUN test -f configure || autoreconf -iv && \
    ./configure && \
    make && \
    make install

WORKDIR /opt/client

# Add and Install Application Code
COPY . /opt/client

RUN pip install paramiko
# Compile
# RUN ghc Client.hs

# Run the client
CMD ["python3", "gen.py"]
