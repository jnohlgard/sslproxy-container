#!/bin/sh
set -eu

if [ $# -eq 0 ]; then
  >&2 printf 'Missing proxyspec\n'
  >&2 printf 'Usage: podman run ... sslproxy <proxyspec>\n\n'
  >&2 printf 'Example:\n  podman run ... sslproxy https 0.0.0.0 10443 sni 443\n'
  sslproxy -h
  exit 1
fi

# use args as a command if the first argument does not start with a dash
case "$1" in
  sslproxy)
    shift
    ;;
  -*|tcp|ssl|http|https|pop3|pop3s|smtp|smtps|autossl)
    ;;
  *)
    exec "$@"
    exit 0
    ;;
esac

# Default values for environment variables
# CA certificate file, PEM format
: "${SSLPROXY_CA_CERT:=/sslproxy/ca/ca.crt}"
# CA private key, PEM format
: "${SSLPROXY_CA_KEY=${SSLPROXY_CA_CERT%.*}.key}"
# Load specific server certificates from this dir, see -t sslproxy option
: "${SSLPROXY_CERT_DIR=/sslproxy/certs}"
# Write on-the-fly certificates to this dir
: "${SSLPROXY_GEN_DIR=/sslproxy/gen}"
# Log all connections to this file. Disable connections log if empty.
: "${SSLPROXY_CONNECT_LOG=/sslproxy/log/connections.log}"
# Write PCAP files in this path. Logs to separate files if the path ends in
# "/", treated as a logspec if the string contains at least one % character,
# otherwise all content is logged to a single file. Disable pcap logging if
# empty. See man 1 sslproxy for details.
: "${SSLPROXY_PCAP_LOG=/sslproxy/log/pcap/}"
# Write unencrypted content to this path. Logs to separate files if the path
# ends in "/", treated as a logspec if the string contains at least one %
# character, otherwise all content is logged to a single file. Disable content
# logging if empty. See man 1 sslproxy for details.
: "${SSLPROXY_CONTENT_LOG=}"

# Generate a root CA if the certificate does not exist
if [ ! -e "${SSLPROXY_CA_CERT}" ]; then
  printf 'Missing CA certificate file %s, generating a new root CA\n' "${SSLPROXY_CA_CERT}"
  : "${SSLPROXY_CA_KEY:=${SSLPROXY_CA_CERT%.*}.key}"
  if [ ! -e "${SSLPROXY_CA_KEY}" ]; then
    mkdir -p "${SSLPROXY_CA_KEY%/*}"
    printf 'Generating root CA key %s\n' "${SSLPROXY_CA_KEY}"
    openssl genrsa -out "${SSLPROXY_CA_KEY}" 4096
  fi
  mkdir -p "${SSLPROXY_CA_CERT%/*}"
  # Generate a generic root CA certificate with 10 year validity
  openssl req -new -nodes -x509 -sha256 \
    -out "${SSLPROXY_CA_CERT}" \
    -key "${SSLPROXY_CA_KEY}" \
    -config /etc/sslproxy/x509v3ca.cnf -extensions v3_ca \
    -subj '/O=SSLproxy Root CA/CN=SSLproxy Root CA/' \
    -set_serial 0 -days 3650
fi
printf 'Using CA certificate for on-the-fly generation from %s\n' "${SSLPROXY_CA_CERT}"
set -- -c "${SSLPROXY_CA_CERT}" "$@"

if [ -n "${SSLPROXY_CA_KEY}" ]; then
  printf 'Using CA certificate key %s\n' "${SSLPROXY_CA_KEY}"
  set -- -k "${SSLPROXY_CA_KEY}" "$@"
else
  printf 'Using CA certificate key embedded inside %s\n' "${SSLPROXY_CA_CERT}"
fi

if [ -n "${SSLPROXY_CERT_DIR}" ]; then
  mkdir -p "${SSLPROXY_CERT_DIR}"
  printf 'Using host certificates from %s\n' "${SSLPROXY_CERT_DIR}"
  set -- -t "${SSLPROXY_CERT_DIR}" "$@"
else
  printf 'Not loading any specific host certificates\n'
fi

if [ -n "${SSLPROXY_GEN_DIR}" ]; then
  mkdir -p "${SSLPROXY_GEN_DIR}"
  printf 'Writing on-the-fly generated certificates to %s\n' "${SSLPROXY_GEN_DIR}"
  set -- -w "${SSLPROXY_GEN_DIR}" "$@"
fi

if [ -n "${SSLPROXY_CONNECT_LOG}" ]; then
  mkdir -p "${SSLPROXY_CONNECT_LOG%/*}"
  printf 'Logging all connections to %s\n' "${SSLPROXY_CONNECT_LOG}"
  set -- -l "${SSLPROXY_CONNECT_LOG}" "$@"
else
  printf 'Not writing a summary connection log\n'
fi

if [ -n "${SSLPROXY_PCAP_LOG}" ]; then
  mkdir -p "${SSLPROXY_PCAP_LOG%/*}"
  case "${SSLPROXY_PCAP_LOG}" in
    */)
      mkdir -p "${SSLPROXY_PCAP_LOG}"
      set -- -Y "${SSLPROXY_PCAP_LOG}" "$@"
      ;;
    *'%'*)
      set -- -y "${SSLPROXY_PCAP_LOG}" "$@"
      ;;
    *)
      set -- -X "${SSLPROXY_PCAP_LOG}" "$@"
      ;;
  esac
  printf 'Logging all traffic as unencrypted PCAP to %s\n' "${SSLPROXY_PCAP_LOG}"
else
  printf 'Not logging traffic content as PCAP\n'
fi

if [ -n "${SSLPROXY_CONTENT_LOG}" ]; then
  mkdir -p "${SSLPROXY_CONTENT_LOG%/*}"
  case "${SSLPROXY_CONTENT_LOG}" in
    */)
      mkdir -p "${SSLPROXY_CONTENT_LOG}"
      set -- -S "${SSLPROXY_CONTENT_LOG}" "$@"
      ;;
    *'%'*)
      set -- -F "${SSLPROXY_CONTENT_LOG}" "$@"
      ;;
    *)
      set -- -L "${SSLPROXY_CONTENT_LOG}" "$@"
      ;;
  esac
  printf 'Logging all content unencrypted to %s\n' "${SSLPROXY_CONTENT_LOG}"
else
  printf 'Not logging content as unencrypted file(s)\n'
fi

printf 'Starting SSLproxy server\n'
printf '\n\n ===== Copy %s to your target device and install it as a trusted root CA\n' "${SSLPROXY_CA_CERT}"
set -x
exec sslproxy -D "$@"
