# live checks for lib/chaki/http.bend against real servers, run by hand:
#   rr bend test/chaki_http_live.bend
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

def main() -> IO(Unit):
  do IO<Unit>:
    +c : Http.Client = Http.Client{Http.Ossl{}, Nil{}, 20000}
    r1 : Result<&1, &1, String, Http.Res> <- Http.fetch(c, "GET", "https://api.github.com/zen", ua(), Nil{})
    IO.print(got("api.github.com/zen over TLS", r1, "200 https://api.github.com/zen"))
    r2 : Result<&1, &1, String, Http.Res> <- Http.fetch(c, "GET", "https://codeberg.org/api/v1/version", ua(), Nil{})
    IO.print(got("codeberg's version", r2, "200 https://codeberg.org/api/v1/version"))
    r3 : Result<&1, &1, String, Http.Res> <- Http.fetch(c, "GET", "http://github.com/", ua(), Nil{})
    IO.print(got("http://github.com/ follows to https", r3, "200 https://github.com/"))
    r4 : Result<&1, &1, String, Http.Res> <- Http.fetch(c, "GET", "https://expired.badssl.com/", ua(), Nil{})
    IO.print(T.ok("an expired certificate is refused", String.starts_with(status.of(r4), "fail: tls with expired.badssl.com")))
