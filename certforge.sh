#!/usr/bin/env bash
#
# certforge — generate a CSR (and optionally a self-signed certificate) from an
# OpenSSL config file.
#
# Two common workflows:
#   1. CSR only (default): hand the CSR to an internal/enterprise CA for signing.
#   2. Self-signed (--self-signed): mint a standalone certificate on the spot.
#
# The private key is either reused (--key) or freshly generated.

set -euo pipefail

# --- defaults ---------------------------------------------------------------
CONFIG=""
KEY=""
OUT_DIR="./out"
NAME=""
BITS="2048"
SELF_SIGNED="false"
DAYS="365"
DAYS_SET="false"
FORCE="false"
SAN_ENTRIES=()

PROG="$(basename "${0}")"

# --- helpers ----------------------------------------------------------------
die() {
    echo "error: ${1}" >&2
    exit 1
}

usage() {
    cat <<EOF
${PROG} — generate a CSR (or self-signed certificate) from an OpenSSL config.

USAGE:
    ${PROG} --config <file.cnf> [--key <file.key>] [--self-signed] [options]

REQUIRED:
    -c, --config FILE   OpenSSL config file describing the subject and extensions.

OPTIONS:
    -k, --key FILE      Reuse an existing private key. If omitted, a new RSA key
                        is generated.
    -o, --out DIR       Output directory (default: ${OUT_DIR}).
    -n, --name NAME     Base name for the output files (default: derived from the
                        config file name).
    -b, --bits N        RSA key size for a newly generated key (default: ${BITS}).
                        Ignored when --key is given.
    -s, --self-signed   Also produce a self-signed certificate instead of only a
                        CSR. Uses the x509_extensions from the config, if present.
    -d, --days N        Validity in days for the self-signed certificate; must be
                        a positive integer (default: ${DAYS}). Only applies with
                        --self-signed.
        --san LIST      Override the config's subjectAltName. May be repeated,
                        and each value may be comma-separated; all entries are
                        merged, e.g. --san DNS:a.example.com --san IP:192.0.2.10.
    -f, --force         Overwrite output files if they already exist.
    -h, --help          Show this help and exit.

OUTPUT (written to the output directory):
    <name>.key          Private key (only when a new key is generated).
    <name>.csr          Certificate Signing Request.
    <name>.crt          Self-signed certificate (only with --self-signed).

EXAMPLES:
    # CSR + new key, to be signed later by an internal CA
    ${PROG} --config server.cnf

    # CSR reusing a key you already hold
    ${PROG} --config server.cnf --key server.key

    # Self-signed certificate valid for two years
    ${PROG} --config server.cnf --self-signed --days 730

    # Override the SAN from the command line (repeat --san to add entries)
    ${PROG} --config server.cnf --san DNS:api.example.com --san IP:192.0.2.20
EOF
}

# --- argument parsing -------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "${1}" in
        -c|--config)      CONFIG="${2:-}"; shift 2 ;;
        -k|--key)         KEY="${2:-}"; shift 2 ;;
        -o|--out)         OUT_DIR="${2:-}"; shift 2 ;;
        -n|--name)        NAME="${2:-}"; shift 2 ;;
        -b|--bits)        BITS="${2:-}"; shift 2 ;;
        -s|--self-signed) SELF_SIGNED="true"; shift ;;
        -d|--days)        DAYS="${2:-}"; DAYS_SET="true"; shift 2 ;;
        --san)            SAN_ENTRIES+=("${2:-}"); shift 2 ;;
        -f|--force)       FORCE="true"; shift ;;
        -h|--help)        usage; exit 0 ;;
        *)                die "unknown option: ${1} (try --help)" ;;
    esac
done

# --- validation -------------------------------------------------------------
command -v openssl >/dev/null 2>&1 || die "openssl not found on PATH"

[[ -n "${CONFIG}" ]] || { usage >&2; echo; die "--config is required"; }
[[ -f "${CONFIG}" ]] || die "config file not found: ${CONFIG}"

if [[ -n "${KEY}" && ! -f "${KEY}" ]]; then
    die "key file not found: ${KEY}"
fi

[[ "${BITS}" =~ ^[0-9]+$ ]] || die "--bits must be a number: ${BITS}"

# --days must be a positive integer, and only applies to self-signed certs.
[[ "${DAYS}" =~ ^[0-9]+$ ]] || die "--days must be a whole number: ${DAYS}"
[[ "${DAYS}" -gt 0 ]] || die "--days must be greater than 0: ${DAYS}"
if [[ "${DAYS_SET}" == "true" && "${SELF_SIGNED}" != "true" ]]; then
    echo "warning: --days only applies with --self-signed; ignoring it" >&2
fi

# Default base name: config file name without its extension.
if [[ -z "${NAME}" ]]; then
    NAME="$(basename "${CONFIG}")"
    NAME="${NAME%.*}"
fi

mkdir -p "${OUT_DIR}"

KEY_OUT="${OUT_DIR}/${NAME}.key"
CSR_OUT="${OUT_DIR}/${NAME}.csr"
CRT_OUT="${OUT_DIR}/${NAME}.crt"

guard_overwrite() {
    if [[ -e "${1}" && "${FORCE}" != "true" ]]; then
        die "refusing to overwrite existing file: ${1} (use --force)"
    fi
}

# --- key --------------------------------------------------------------------
if [[ -n "${KEY}" ]]; then
    echo ">> Using existing private key: ${KEY}"
    KEY_IN="${KEY}"
else
    guard_overwrite "${KEY_OUT}"
    echo ">> Generating new ${BITS}-bit RSA private key: ${KEY_OUT}"
    openssl genrsa -out "${KEY_OUT}" "${BITS}"
    chmod 600 "${KEY_OUT}"
    KEY_IN="${KEY_OUT}"
fi

# --san values are injected as a single -addext, which takes precedence over any
# subjectAltName in the config file. The flag may be repeated, and each value may
# itself be comma-separated; all entries are merged into one subjectAltName.
SAN_ARGS=()
if [[ ${#SAN_ENTRIES[@]} -gt 0 ]]; then
    SAN_JOINED="$(IFS=,; echo "${SAN_ENTRIES[*]}")"
    echo ">> Overriding subjectAltName: ${SAN_JOINED}"
    SAN_ARGS=(-addext "subjectAltName=${SAN_JOINED}")
fi

# --- CSR --------------------------------------------------------------------
guard_overwrite "${CSR_OUT}"
echo ">> Generating CSR: ${CSR_OUT}"
openssl req -new -key "${KEY_IN}" -out "${CSR_OUT}" -config "${CONFIG}" "${SAN_ARGS[@]}"

# --- self-signed certificate (optional) ------------------------------------
if [[ "${SELF_SIGNED}" == "true" ]]; then
    guard_overwrite "${CRT_OUT}"
    echo ">> Generating self-signed certificate (${DAYS} days): ${CRT_OUT}"
    openssl req -x509 -new -nodes -key "${KEY_IN}" -days "${DAYS}" \
        -out "${CRT_OUT}" -config "${CONFIG}" "${SAN_ARGS[@]}"
fi

# --- summary ----------------------------------------------------------------
echo
echo "Done. Artifacts:"
[[ -n "${KEY}" ]] || echo "  key : ${KEY_OUT}"
echo "  csr : ${CSR_OUT}"
[[ "${SELF_SIGNED}" == "true" ]] && echo "  crt : ${CRT_OUT}"
echo
if [[ "${SELF_SIGNED}" != "true" ]]; then
    echo "Next step: submit ${CSR_OUT} to your CA for signing."
fi
