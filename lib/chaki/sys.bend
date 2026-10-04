# sys: the only foreign code in chaki besides ossl. A TCP dial that resolves and tries
# every address under one deadline, a recv with a deadline, the wall clock, and the
# terminal. Mongoose's OS layer is the model: thin, and one file per side (effs/sys.c,
# effs/sys.js).
import Base

# a TCP connection to host:port. host is a name or an IPv4/IPv6 literal. getaddrinfo's
# answer (AF_UNSPEC) is reordered so the families alternate, each family keeping its own
# order and the first address's family leading (RFC 8305 4), then the addresses are tried
# in turn; each gets a fair share of what is left of ms, so a black-holed address cannot eat
# a later family's turn. ms bounds the whole dial. The Socket is Base's, non-blocking, so
# Base's TCP effects and Socket.close work on it too.
def dial(host: String, port: U32, ms: U32) -> IO(Result<&1, &1, U32 & String, Socket>):
  import "./effs/sys.c"
  import "./effs/sys.js"

# up to max bytes, waiting at most ms. Done{[]} means the peer closed. A miss is
# Fail{(ETIMEDOUT, ..)}.
def recv(sock: Socket, max: U32, ms: U32) ->
  IO(Socket & Result<&1, &1, U32 & String, List<&2, U32>>):
  import "./effs/sys.c"
  import "./effs/sys.js"

# all of data, or a failure. Base's TCP.send_bytes already sends everything, parking until
# a full socket drains, so this is that call.
def send(sock: Socket, data: List<&2, U32>) ->
  IO(Socket & Result<&1, &1, U32 & String, Unit>):
  TCP.send_bytes(sock, data)

# Unix time in seconds (wall clock, not monotonic)
def now() -> IO(U32):
  import "./effs/sys.c"
  import "./effs/sys.js"

# libc's isatty answers 1 or 0; the C and JS sides hand that number over as a U32.
def isatty.raw(fd: U32) -> IO(U32):
  import "./effs/sys.c"
  import "./effs/sys.js"

# whether fd (0, 1, 2) is a terminal
def isatty(fd: U32) -> IO(Bool):
  do IO<Bool>:
    n : U32 <- isatty.raw(fd)
    return U32.is_ne(n, 0)

# the terminal's columns on stdout, 0 when it isn't a terminal or won't say
def cols() -> IO(U32):
  import "./effs/sys.c"
  import "./effs/sys.js"

# the terminal's rows on stdout, 0 when it isn't a terminal or won't say
def rows() -> IO(U32):
  import "./effs/sys.c"
  import "./effs/sys.js"
