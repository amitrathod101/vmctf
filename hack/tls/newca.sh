#!/bin/sh

# posix complaint
# verified by https://www.shellcheck.net

#
# USAGE: newca.sh
#    This script generates a PEM-formatted, self-signed CA.
#    The generated key and certificate are printed to STDOUT unless
#    TLS_KEY_OUT and TLS_CRT_OUT are both set or TLS_PEM_OUT is set.
#
# CONFIGURATION
#     This script is configured via the following environment
#     variables:
#

# The paths to the generated key and certificate files.
# If TLS_KEY_OUT, TLS_CRT_OUT, and TLS_PEM_OUT are all unset then
# the generated key and certificate are printed to STDOUT.
#TLS_KEY_OUT=ca.key
#TLS_CRT_OUT=ca.crt

# The path to the combined key and certificate file.
# Setting this value overrides TLS_KEY_OUT and TLS_CRT_OUT.
#TLS_PEM_OUT=ca.pem

# The strength of the generated certificate
TLS_DEFAULT_BITS=${TLS_DEFAULT_BITS:-2048}

# The number of days until the certificate expires. The default
# value is 100 years.
TLS_DEFAULT_DAYS=${TLS_DEFAULT_DAYS:-36500}

# The components that make up the certificate's distinguished name.
TLS_COUNTRY_NAME=${TLS_COUNTRY_NAME:-US}
TLS_STATE_OR_PROVINCE_NAME=${TLS_STATE_OR_PROVINCE_NAME:-California}
TLS_LOCALITY_NAME=${TLS_LOCALITY_NAME:-Palo Alto}
TLS_ORG_NAME=${TLS_ORG_NAME:-VMware}
TLS_OU_NAME=${TLS_OU_NAME:-CNX}
TLS_COMMON_NAME=${TLS_COMMON_NAME:-CNX CICD CA}
TLS_EMAIL=${TLS_EMAIL:-cnx@vmware.com}

# Make a temporary directory and switch to it.
OLDDIR=$(pwd)
MYTEMP=$(mktemp -d) && cd "$MYTEMP" || exit 1

# Returns the absolute path of the provided argument.
abs_path() {
  if [ "$(printf %.1s "${1}")" = "/" ]; then 
    echo "${1}"
  else
    echo "${OLDDIR}/${1}"
  fi
}

# Write the SSL config file to disk.
cat > ssl.conf <<EOF
[ req ]
default_bits           = ${TLS_DEFAULT_BITS}
encrypt_key            = no
default_md             = sha1
prompt                 = no
utf8                   = yes
distinguished_name     = dn
req_extensions         = ext
x509_extensions        = ext

[ dn ]
countryName            = ${TLS_COUNTRY_NAME}
stateOrProvinceName    = ${TLS_STATE_OR_PROVINCE_NAME}
localityName           = ${TLS_LOCALITY_NAME}
organizationName       = ${TLS_ORG_NAME}
organizationalUnitName = ${TLS_OU_NAME}
commonName             = ${TLS_COMMON_NAME}
emailAddress           = ${TLS_EMAIL}

[ ext ]
basicConstraints       = critical, CA:TRUE
keyUsage               = critical, cRLSign, digitalSignature, keyCertSign
subjectKeyIdentifier   = hash
EOF

EXIT_CODE=0

# Generate a a self-signed certificate:
openssl req -config ssl.conf \
            -new \
            -nodes \
            -x509 \
            -days "${TLS_DEFAULT_DAYS}" \
            -keyout key.pem \
            -out crt.pem > gen.log 2>&1
EXIT_CODE=$?

if [ "${EXIT_CODE}" -eq "0" ]; then

  # "Fix" the private key. Keys generated by "openssl req" are not
  # in the correct format. 
  openssl rsa -in key.pem -out key.pem.fixed
  mv -f key.pem.fixed key.pem

  # Generate a combined PEM file at TLS_PEM_OUT.
  if [ -n "${TLS_PEM_OUT}" ]; then
    PEM_FILE=$(abs_path "${TLS_PEM_OUT}")
    mkdir -p "$(dirname "${PEM_FILE}")"
    cat key.pem > "${PEM_FILE}"
    cat crt.pem >> "${PEM_FILE}"
  fi

  # Copy the key and crt files to TLS_KEY_OUT and TLS_CRT_OUT.
  if [ -n "${TLS_KEY_OUT}" ]; then
    KEY_FILE=$(abs_path "${TLS_KEY_OUT}")
    mkdir -p "$(dirname "${KEY_FILE}")"
    cp -f key.pem "${KEY_FILE}"
  fi

  if [ -n "${TLS_CRT_OUT}" ]; then
    CRT_FILE=$(abs_path "${TLS_CRT_OUT}")
    mkdir -p "$(dirname "${CRT_FILE}")"
    cp -f crt.pem "${CRT_FILE}"
  fi

  # Print the key and certificate to STDOUT.
  cat key.pem && echo && cat crt.pem
else
  cat gen.log || true
fi

if [ "${EXIT_CODE}" -eq "0" ] && [ "${TLS_PLAIN_TEXT}" = "true" ]; then
  echo && openssl x509 -in crt.pem -noout -text
fi

# Switch to the previous directory.
cd "${OLDDIR}" || exit 1

# Remove the temporary directory.
rm -fr "${MYTEMP}"

exit "${EXIT_CODE}"