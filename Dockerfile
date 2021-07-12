# base is what all other stages derive from
FROM ubuntu:20.04 as base

RUN apt-get update

RUN DEBIAN_FRONTEND=noninteractive apt-get -y install \
    libmicrohttpd-dev libjansson-dev libssl-dev libsofia-sip-ua-dev libglib2.0-dev libopus-dev libogg-dev libcurl4-openssl-dev liblua5.3-dev libconfig-dev libavcodec-dev

# builder is a stage that configures the tooling and deps needed to do a build
FROM base as builder

RUN DEBIAN_FRONTEND=noninteractive apt-get -y install \
    curl g++-10 git pkg-config gengetopt libtool automake python3 python3-pip python3-setuptools python3-dev python3-wheel ninja-build gdb

RUN update-alternatives \
    --install /usr/bin/gcc gcc /usr/bin/gcc-10 100 --slave /usr/bin/g++ g++ /usr/bin/g++-10 --slave /usr/bin/gcov gcov /usr/bin/gcov-10

RUN pip3 install meson

WORKDIR /tmp

ENV LIBNICE_VERSION=0.1.18
ENV LIBSRTP_VERSION=v2.3.0
ENV JANUSGATEWAY_VERSION=v0.10.10

RUN \
    DIR=/tmp/libnice && \
    mkdir -p ${DIR} && \
    cd ${DIR} && \
    curl -sLf https://github.com/libnice/libnice/archive/${LIBNICE_VERSION}.tar.gz | tar -zx --strip-components=1 && \
    meson --prefix=/usr build/ && \
    ninja -C build && \
    ninja -C build install

RUN \
    DIR=/tmp/libsrtp && \
    mkdir -p ${DIR} && \
    cd ${DIR} && \
    curl -sLf https://github.com/cisco/libsrtp/archive/${LIBSRTP_VERSION}.tar.gz | tar -zx --strip-components=1 && \
    ./configure --prefix=/usr --enable-openssl && \
    make shared_library && \
    make install

RUN \
    DIR=/tmp/janus-gateway && \
    mkdir -p ${DIR} && \
    cd ${DIR} && \
    curl -sLf https://github.com/meetecho/janus-gateway/archive/${JANUSGATEWAY_VERSION}.tar.gz | tar -zx --strip-components=1 && \
    sh autogen.sh && \
    ./configure --prefix=/opt/janus \
                --disable-rabbitmq \
                --disable-mqtt \
                --disable-unix-sockets \
                --disable-websockets \
                --disable-all-handlers \
                --disable-all-plugins && \
    make && \
    make configs && \
    make install

# copy the remaining libs directly into janus so we can run on "base"
RUN find /tmp/libnice/ -name "*.so*" | xargs cp -r -t /opt/janus/bin/
RUN find /tmp/libsrtp/ -name "*.so*" | xargs cp -r -t /opt/janus/bin/

WORKDIR /app
COPY . /app

# we need these for devcontainer, so we do them directly in builder
ENV DIR=/app CC=gcc-10 CXX=g++-10
RUN meson --buildtype=debugoptimized build/
RUN mkdir -p /opt/janus/lib/janus/plugins/

# app is a stage just for building our app
FROM builder as app

WORKDIR /app/build
RUN ninja && ninja install

# runner is a stage for running our app with minimal deps (smaller image)
FROM base as runner
COPY --from=app /opt/janus/ /opt/janus/

# Janus API HTTP
EXPOSE 8088/tcp
# Janus API HTTPS
EXPOSE 8089/tcp
# FTL Ingest Handshake
EXPOSE 8084/tcp
# FTL Media
EXPOSE 9000-9100/udp
# RTP Media
EXPOSE 20000-20100/udp
# NOTE: Usually we'd want a way larger Media/RTP port range
# but Docker is extremely slow at opening huge port ranges
# (see moby/moby#14288)

ENV LD_LIBRARY_PATH=/opt/janus/bin
RUN mkdir -p /opt/janus/lib/janus/plugins
CMD exec /opt/janus/bin/janus --rtp-port-range=20000-20100 --nat-1-1=${DOCKER_IP}
