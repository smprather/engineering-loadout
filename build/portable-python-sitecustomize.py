# LOADOUT_CA_HOOK -- installed by build/import-portable-python.
"""Use the host CA bundle from the loadout portable Python.

The EL8 portable build compiles OpenSSL's default certificate paths against the
build prefix (/opt/cpython3150p/ssl), which does not exist after deployment.
Without a system bundle, every HTTPS request (urllib, pip, check-versions,
update) fails with CERTIFICATE_VERIFY_FAILED: unable to get local issuer
certificate.

SSL_CERT_FILE and SSL_CERT_DIR are never overridden: a caller that sets either
one keeps full control. Otherwise the first existing system bundle is used.

The portable build's own startup hook (OPENSSL_MODULES, TCL_LIBRARY,
TK_LIBRARY and its single RHEL CA path) was renamed to sitecustomize_portable.py
when this file was injected; it still runs, after this CA setup. The same file
is injected into the python-build-standalone interpreters, whose own hook (when
a build ships one) is renamed to sitecustomize_pbs.py; whichever exists runs.
"""

import os

_CA_BUNDLES = (
    "/etc/ssl/certs/ca-certificates.crt",
    "/etc/pki/tls/certs/ca-bundle.crt",
    "/etc/ssl/cert.pem",
)

if not os.environ.get("SSL_CERT_FILE") and not os.environ.get("SSL_CERT_DIR"):
    for _bundle in _CA_BUNDLES:
        if os.path.isfile(_bundle):
            os.environ["SSL_CERT_FILE"] = _bundle
            break

try:
    import importlib

    for _hook in ("sitecustomize_portable", "sitecustomize_pbs"):
        try:
            importlib.import_module(_hook)  # the build's own hook, when present
        except ImportError:
            pass
except ImportError:
    pass
