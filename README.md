# certforge

Small, dependency-light OpenSSL helpers for issuing X.509 certificates.

`certforge` gives you two tools:

- **`certforge.sh`** — a focused CLI that turns an OpenSSL config file into a
  **CSR** (to be signed by your own/internal CA) or, optionally, a
  **self-signed certificate**. Bring your own private key or let it generate one.
- **`genCA.sh`** — a batch script that stands up a self-signed root CA and issues
  a certificate for every device listed in `inventory.json`. Handy for lab and
  test fabrics.

Everything is plain Bash + `openssl` (and `jq` for the batch script). No PKI
frameworks, no daemons.

---

## Requirements

- `bash` 4+
- `openssl` 1.1+ / 3.x
- `jq` (only for `genCA.sh`)

---

## `certforge.sh` — CSR / self-signed CLI

The typical use is generating a CSR that an **internal CA** then signs. The same
tool can also produce a self-signed certificate when you don't need an external
signer.

### Usage

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

---

## `genCA.sh` — batch CA for a device inventory

`genCA.sh` builds a self-signed **root CA** and then issues a signed certificate
for each device in `inventory.json`. It's aimed at spinning up certificates for a
lab fabric in one shot.

```bash
./genCA.sh
```

- Root CA settings come from [`root-self-signed.cnf`](root-self-signed.cnf).
- Devices come from [`inventory.json`](inventory.json):

  ```json
  {
    "devices": [
      { "hostname": "leaf1", "ip_address": "172.20.20.101", "kind": "server" },
      { "hostname": "client1", "ip_address": "192.168.1.1",  "kind": "client" }
    ]
  }
  ```

- `kind: server` certificates get a `subjectAltName` with the device IP;
  `kind: client` certificates omit it.
- Output lands under `./ca/<hostname>/` (root under `./ca/root/`), with OpenSSL's
  CA database in `./demoCA/`.

> **Note:** the shipped configs use placeholder values (`example.com`, `US`, …).
> Edit them for your own environment before use.

---

## Security notes

- Generated private keys, CSRs and certificates are **git-ignored** by default —
  don't commit real keys.
- Newly generated keys are written with `600` permissions.
- Self-signed certificates are fine for labs and internal testing; for anything
  public-facing, get the CSR signed by a trusted CA.

## License

MIT — see [`LICENSE`](LICENSE) if present, otherwise use freely.
