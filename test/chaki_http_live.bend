# live checks for lib/chaki/http.bend against real servers, run by hand:
#   bend test/chaki_http_live.bend
import Base
import ../lib/chaki/bytes.bend as Bytes
import ../lib/chaki/http1.bend as Http1
import ../lib/chaki/http.bend as Http
import ../lib/chaki/check.bend as T

def status.of(r: Result<&1, &1, String, Http.Res>) -> String:
  match r:
    case Done{Http.Res{+status, hs, b, u}}:
      U32.show(status) ++ " " ++ u
    case Fail{w}:
      "fail: " ++ w

def got(+name: String, r: Result<&1, &1, String, Http.Res>, +want: String) -> String:
  T.eq(name, status.of(r), want)

def ua() -> List<&2, Http1.Field()>:
  [("user-agent", "chaki")]

def refused.said(+name: String, +host: String, +said: String) -> String:
  T.ok(name ++ " is refused (" ++ said ++ ")", String.starts_with(said, "fail: tls with " ++ host))

def refused(+name: String, +host: String, r: Result<&1, &1, String, Http.Res>) -> String:
  refused.said(name, host, status.of(r))

# the same requests over one transport
def round(+tag: String, +c: Http.Client) -> IO(Unit):
  do IO<Unit>:
    r1 : Result<&1, &1, String, Http.Res> <- Http.fetch(c, "GET", "https://api.github.com/zen", ua(), Nil{})
    IO.print(got(tag ++ " api.github.com/zen", r1, "200 https://api.github.com/zen"))
    r2 : Result<&1, &1, String, Http.Res> <- Http.fetch(c, "GET", "https://codeberg.org/api/v1/version", ua(), Nil{})
    IO.print(got(tag ++ " codeberg's version", r2, "200 https://codeberg.org/api/v1/version"))
    r3 : Result<&1, &1, String, Http.Res> <- Http.fetch(c, "GET", "http://github.com/", ua(), Nil{})
    IO.print(got(tag ++ " http://github.com/ follows to https", r3, "200 https://github.com/"))
    r4 : Result<&1, &1, String, Http.Res> <- Http.fetch(c, "GET", "https://expired.badssl.com/", ua(), Nil{})
    IO.print(refused(tag ++ " an expired certificate", "expired.badssl.com", r4))
    r5 : Result<&1, &1, String, Http.Res> <- Http.fetch(c, "GET", "https://wrong.host.badssl.com/", ua(), Nil{})
    IO.print(refused(tag ++ " the wrong host", "wrong.host.badssl.com", r5))
    r6 : Result<&1, &1, String, Http.Res> <- Http.fetch(c, "GET", "https://self-signed.badssl.com/", ua(), Nil{})
    IO.print(refused(tag ++ " a self-signed certificate", "self-signed.badssl.com", r6))
    r7 : Result<&1, &1, String, Http.Res> <- Http.fetch(c, "GET", "https://untrusted-root.badssl.com/", ua(), Nil{})
    IO.print(refused(tag ++ " an untrusted root", "untrusted-root.badssl.com", r7))

def bend.round(r: Result<&1, &1, U32 & String, Http.Client>) -> IO(Unit):
  match r:
    case Done{c}:
      round("bend:", c)
    case Fail{(n, w)}:
      IO.print("FAIL bend: no client: " ++ w)

def main() -> IO(Unit):
  do IO<Unit>:
    round("ossl:", Http.Client{Http.Ossl{}, Nil{}, 20000})
    b : Result<&1, &1, U32 & String, Http.Client> <- Http.client(Http.Bend{}, 20000)
    bend.round(b)
