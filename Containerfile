FROM registry.fedoraproject.org/fedora-minimal:latest AS base
RUN microdnf install -y \
  openssl \
  libpcap \
  sqlite \
  libevent \
  libnet \
  man \
  && microdnf clean all -y
FROM base AS builder
RUN microdnf install -y --nodocs --setopt install_weak_deps=0 \
  gcc binutils make \
  openssl-devel \
  libpcap-devel \
  sqlite-devel \
  libevent-devel \
  libnet-devel \
  wget unzip \
  git-core \
  && microdnf clean all -y
ARG SSLPROXY_REPO_URL=https://github.com/sonertari/SSLproxy.git
RUN mkdir -p /work /opt/sslproxy && \
  git clone ${SSLPROXY_REPO_URL} /work/SSLproxy && \
  make -C /work/SSLproxy PREFIX=/usr all install

FROM base
RUN printf '%s\n' 'sslproxy:x:1000:1000::/sslproxy:/bin/bash' >> /etc/passwd && \
  printf '%s\n' 'sslproxy:x:1000:' >> /etc/group && \
  mkdir -p /sslproxy/cert/gen /sslproxy/log/pcap /sslproxy/log/content && \
  chown -R sslproxy:sslproxy /sslproxy
COPY --from=builder /usr/bin/sslproxy /usr/bin/sslproxy
COPY --from=builder /usr/share/examples/sslproxy/sslproxy.conf /etc/sslproxy/sslproxy.conf.example
COPY --from=builder /usr/share/man/man1/sslproxy.1 /usr/share/man/man1/sslproxy.1
COPY --from=builder /usr/share/man/man5/sslproxy.conf.5 /usr/share/man/man5/sslproxy.conf.5
EXPOSE 10443
VOLUME /sslproxy
WORKDIR /sslproxy
USER sslproxy
ENTRYPOINT ["/usr/bin/sslproxy"]
CMD ["-h"]
