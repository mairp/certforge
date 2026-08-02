# certforge

Small, dependency-light OpenSSL CLI for issuing X.509 certificates.

**`certforge.sh`** turns an OpenSSL config file into a **CSR** (to be signed by
your own/internal CA) or, optionally, a **self-signed certificate**. Bring your
own private key or let it generate one.

It's plain Bash + `openssl` — no PKI frameworks, no daemons.

---

## Requirements

- `bash` 4+
- `openssl` 1.1+ / 3.x

---

## Usage

The typical use is generating a CSR that an **internal CA** then signs. The same
tool can also produce a self-signed certificate when you don't need an external
signer.

```
certforge.sh --config <file.cnf> [--key <file.key>] [--self-signed] [options]
```

| Option | Description |
| --- | --- |
| `-c, --config FILE` | **Required.** OpenSSL config describing the subject and extensions. |
| `-k, --key FILE` | Reuse an existing private key. If omitted, a new RSA key is generated. |
| `-o, --out DIR` | Output directory (default: `./out`). |
| `-n, --name NAME` | Base name for output files (default: derived from the config file name). |
| `-b, --bits N` | RSA key size for a newly generated key (default: `2048`). Ignored with `--key`. |
| `-s, --self-signed` | Also emit a self-signed certificate instead of only a CSR. |
| `-d, --days N` | Validity in days for the self-signed cert (default: `365`). |
| `-f, --force` | Overwrite existing output files. |
| `-h, --help` | Show help. |

### Inputs and outputs

**Input** is an OpenSSL config file (`.cnf`) plus, optionally, an existing key.
The tool covers three cases:

1. **`.cnf` only** → generates a fresh private key **and** a CSR.
2. **`.cnf` + `.key`** → generates a CSR using the key you already hold.
3. **`--self-signed`** → additionally signs the request with that key to produce
   a ready-to-use certificate.

**Output** (in the chosen directory):

| File | When |
| --- | --- |
| `<name>.key` | Only when a new key is generated. |
| `<name>.csr` | Always. |
| `<name>.crt` | Only with `--self-signed`. |

### Examples

```bash
# 1) CSR + new key — to be signed later by an internal CA
./certforge.sh --config examples/server.cnf

# 2) CSR reusing a private key you already have
./certforge.sh --config examples/server.cnf --key server.key

# 3) Self-signed certificate, valid for two years
./certforge.sh --config examples/server.cnf --self-signed --days 730

# 4) Custom key size, output directory and file name
./certforge.sh --config examples/server.cnf --bits 4096 --out ./certs --name web01
```

After case 1 or 2, submit the resulting `<name>.csr` to your CA. To inspect it:

```bash
openssl req -in out/server.csr -noout -text
```

### Writing the config

`certforge.sh` passes your `.cnf` straight to `openssl req`, so anything OpenSSL
understands works — including Subject Alternative Names. A ready-to-copy starting
point lives in [`examples/server.cnf`](examples/server.cnf):

```ini
[ req ]
prompt             = no
default_bits       = 2048
distinguished_name = req_distinguished_name
req_extensions     = req_ext
x509_extensions    = x509_ext

[ req_distinguished_name ]
countryName            = US
stateOrProvinceName    = California
localityName           = San Francisco
organizationName       = Example Org
organizationalUnitName = Engineering
commonName             = server.example.com

[ req_ext ]
subjectAltName = @alt_names

[ x509_ext ]
subjectAltName   = @alt_names
basicConstraints = CA:FALSE
keyUsage         = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[ alt_names ]
DNS.1 = server.example.com
IP.1  = 192.0.2.10
```

For standing up your own CA, [`examples/self-signed-ca.cnf`](examples/self-signed-ca.cnf)
is a template with the right CA extensions (`CA:TRUE`, cert/CRL signing):

```bash
./certforge.sh --config examples/self-signed-ca.cnf --self-signed --days 3650 --name my-ca
# -> my-ca.key / my-ca.crt — a CA that can then sign other CSRs
```

### End-to-end: signing a `certforge` CSR with an internal CA

The main workflow is generating a CSR with `certforge.sh` and having your
**internal CA** sign it. Below is a complete, runnable example using a local
OpenSSL CA to play the part of that internal CA.

**1. Set up the internal CA** (you already have this in a real environment):

```bash
# Internal root CA key + self-signed CA certificate
openssl genrsa -out internal-ca.key 4096
openssl req -x509 -new -nodes -key internal-ca.key -sha256 -days 3650 \
  -subj "/C=US/O=Example Org/OU=IT/CN=Example Internal Root CA" \
  -out internal-ca.crt
```

**2. Generate the server key + CSR with `certforge`:**

```bash
./certforge.sh --config examples/server.cnf --name web01 --out .
# -> web01.key  (private key)
# -> web01.csr  (submit this to the CA)
```

**3. Have the internal CA sign the CSR.** Provide an extensions file so the
signed certificate keeps its SANs (a CA does not copy them from the CSR by
default):

```bash
cat > web01-ext.cnf <<'EOF'
basicConstraints = CA:FALSE
keyUsage         = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName   = @alt_names
[ alt_names ]
DNS.1 = server.example.com
IP.1  = 192.0.2.10
EOF

openssl x509 -req -in web01.csr \
  -CA internal-ca.crt -CAkey internal-ca.key -CAcreateserial \
  -days 825 -sha256 -extfile web01-ext.cnf -out web01.crt
```

**4. Verify the issued certificate against the CA:**

```bash
openssl verify -CAfile internal-ca.crt web01.crt
# web01.crt: OK

openssl x509 -in web01.crt -noout -issuer -subject -ext subjectAltName
# issuer=C=US, O=Example Org, OU=IT, CN=Example Internal Root CA
# subject=..., CN=server.example.com
# X509v3 Subject Alternative Name:
#     DNS:server.example.com, IP Address:192.0.2.10
```

You now have `web01.key` + `web01.crt` signed by your internal CA. Deploy the
key and certificate to the server, and distribute `internal-ca.crt` to clients
that need to trust it.

---

## Security notes

- Generated private keys, CSRs and certificates are **git-ignored** by default —
  don't commit real keys.
- Newly generated keys are written with `600` permissions.
- Self-signed certificates are fine for labs and internal testing; for anything
  public-facing, get the CSR signed by a trusted CA.

## License

MIT — see [`LICENSE`](LICENSE) if present, otherwise use freely.
