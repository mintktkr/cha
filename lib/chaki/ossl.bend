# ossl: TLS through the system's OpenSSL 3, loaded with dlopen at run time, so the
# binary links nothing extra. It takes a socket Base already connected, always verifies
# the chain against the system's trust store and the certificate against the host, and
# refuses anything below TLS 1.2. chaki's fallback transport.
import Base

# Whether libssl 3 loads; CHAKI_LIBSSL overrides its path.
def available() -> IO(Bool):
  import "./effs/ossl.c"
  import "./effs/ossl.js"

# A TLS client handshake on a connected socket. Host is the name to verify and to send
# as SNI; ALPN offers "http/1.1" only. ms bounds the whole handshake.
def connect(sock: Socket, host: String, ms: U32) ->
  IO(Socket & Result<&1, &1, U32 & String, Unit>):
  import "./effs/ossl.c"
  import "./effs/ossl.js"

# All of data, or a failure.
def send(sock: Socket, data: List<&2, U32>) ->
  IO(Socket & Result<&1, &1, U32 & String, Unit>):
  import "./effs/ossl.c"
  import "./effs/ossl.js"

# Up to max bytes of plaintext, waiting at most ms. Done{[]} once the peer sent its
# close_notify; a peer that closed without one fails with ECONNRESET. A max of 0 fails
# with EINVAL, as Base's TCP.recv_bytes does.
def recv(sock: Socket, max: U32, ms: U32) ->
  IO(Socket & Result<&1, &1, U32 & String, List<&2, U32>>):
  import "./effs/ossl.c"
  import "./effs/ossl.js"

# close_notify, the session, then the socket. A socket without a session is just closed.
def close(sock: Socket) -> IO(Unit):
  import "./effs/ossl.c"
  import "./effs/ossl.js"
