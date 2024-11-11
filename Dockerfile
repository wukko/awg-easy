FROM alpine AS awg-build

RUN apk add git go musl-dev linux-headers gcc make

# Build amneziawg-go
ADD https://github.com/amnezia-vpn/amneziawg-go.git#2e3f7d122ca8ef61e403fddc48a9db8fccd95dbf /awg-go
ARG CGO_ENABLED=1

# taken from amneziawg-go/Dockerfile
RUN cd /awg-go && \
    go build -ldflags '-linkmode external -extldflags "-fno-PIC -static"' -v -o /awg-go/awg-go.bin

# Build amneziawg-tools
ADD https://github.com/amnezia-vpn/amneziawg-tools.git#c0b400c6dfc046f5cae8f3051b14cb61686fcf55 /awg-tools
RUN cd /awg-tools/src && \
    make -j$(nproc)

# As a workaround we have to build on nodejs 18
# nodejs 20 hangs on build with armv6/armv7
FROM docker.io/library/node:18-alpine AS build_node_modules

# Update npm to latest
RUN npm install -g npm@latest

# Copy Web UI
COPY src /app
WORKDIR /app
RUN npm ci --omit=dev &&\
    mv node_modules /node_modules

# Copy build result to a new image.
# This saves a lot of disk space.
FROM docker.io/library/node:lts-alpine
HEALTHCHECK CMD /usr/bin/timeout 5s /bin/sh -c "/usr/bin/wg show | /bin/grep -q interface || exit 1" --interval=1m --timeout=5s --retries=3
COPY --from=build_node_modules /app /app

COPY --from=awg-build /awg-go/awg-go.bin /usr/bin/amneziawg-go
COPY --from=awg-build /awg-tools/src/wg /usr/bin/awg
COPY --from=awg-build /awg-tools/src/wg-quick/linux.bash /usr/bin/awg-quick

RUN mkdir -pm 0777 /etc/amnezia/amneziawg

RUN ln -s /usr/bin/awg /usr/bin/wg && \
    ln -s /usr/bin/awg-quick /usr/bin/wg-quick && \
    ln -s /etc/amnezia/amneziawg /etc/wireguard

# Move node_modules one directory up, so during development
# we don't have to mount it in a volume.
# This results in much faster reloading!
#
# Also, some node_modules might be native, and
# the architecture & OS of your development machine might differ
# than what runs inside of docker.
COPY --from=build_node_modules /node_modules /node_modules

# Copy the needed wg-password scripts
COPY --from=build_node_modules /app/wgpw.sh /bin/wgpw
RUN chmod +x /bin/wgpw

# Install Linux packages
RUN apk add --no-cache \
    bash \
    dpkg \
    dumb-init \
    iptables \
    iproute2 \
    iptables-legacy

# Use iptables-legacy
RUN update-alternatives --install /sbin/iptables iptables /sbin/iptables-legacy 10 --slave /sbin/iptables-restore iptables-restore /sbin/iptables-legacy-restore --slave /sbin/iptables-save iptables-save /sbin/iptables-legacy-save

# Set Environment
ENV DEBUG=Server,WireGuard

# Run Web UI
WORKDIR /app
CMD ["/usr/bin/dumb-init", "node", "server.js"]
