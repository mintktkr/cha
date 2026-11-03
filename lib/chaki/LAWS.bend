# laws: what chaki promises, stated before it is proven. Each law is a claim about a pure
# module; PROOF.bend beside this file proves it. The gate is scripts/check.sh: this file's
# PROOF.bend must exit 0 with ALL PROOFS CHECK, so no law here may lean on @unsafe or foreign
# code, and `bend lib/chaki/PROOF.bend --verdict` rechecks every proof with the BendTT kernel.
# sys, ossl, tlsio and http's IO stay out: their decisions move into pure defs that are stated
# here. Law names start with their module (b64_, tls_, ...).
import Base
import ./bytes.bend as Bytes
import ./utf8.bend as Utf8
import ./b64.bend as B64
import ./time.bend as Time
import ./width.bend as Width
import ./url.bend as Url
import ./http1.bend as Http1
import ./sha2.bend as Sha2
import ./chacha.bend as Chacha
import ./aes.bend as Aes
import ./x25519.bend as X25519
import ./big.bend as Big
import ./rsa.bend as Rsa
import ./ecdsa.bend as Ecdsa
import ./asn1.bend as Asn1
import ./x509.bend as X509
import ./x509v.bend as X509v
import ./tlsmsg.bend as Tlsmsg
import ./tls.bend as Tls

# bytes, utf8, b64 [enc]
# ----------------------

# end enc

# json [json]
# -----------

# end json

# url [url]
# ---------

# end url

# http1 [http1]
# -------------

# end http1

# time, width [time]
# ------------------

# end time

# sha2, chacha [hash]
# -------------------

# end hash

# aes, x25519 [block]
# -------------------

# end block

# big, rsa, ecdsa [pk]
# --------------------

# end pk

# asn1, x509, x509v [x509]
# ------------------------

# end x509

# tlsmsg, tls [tls]
# -----------------

# end tls

# http (its pure decisions) [http]
# --------------------------------

# end http
