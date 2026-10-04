# offline checks for lib/chaki/http.bend: two local plain-HTTP servers on two ports (two
# origins) answer canned responses, and /echo reports what reached it, so the redirect rules
# (credentials dropped across origins, 303 to GET, 307 keeps the POST) show end to end.
import Base
import ../lib/chaki/bytes.bend as Bytes
import ../lib/chaki/url.bend as Url
import ../lib/chaki/http1.bend as Http1
import ../lib/chaki/sys.bend as Sys
import ../lib/chaki/http.bend as Http
import ../lib/chaki/check.bend as T

def A() -> U32:
  14811

def B() -> U32:
  14812

# The servers
# -----------

def nth(xs: List<&2, String>, n: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, xs, n), "")

def target.of(+req: String) -> String:
  nth(String.split(req, ' '), 1n)

def method.of(+req: String) -> String:
  nth(String.split(req, ' '), 0n)

def yes(b: Bool) -> String:
  match b:
    case True{}:
      "yes"
    case False{}:
      "no"

def ok(+body: String) -> String:
  "HTTP/1.1 200 OK\r\ncontent-length: " ++ Nat.show(String.length(body)) ++ "\r\n\r\n" ++ body

def moved(+code: String, +loc: String) -> String:
  "HTTP/1.1 " ++ code ++ " Moved\r\nlocation: " ++ loc ++ "\r\ncontent-length: 0\r\n\r\n"

# what reached /echo: the method, and whether authorization and content-type came along
def echo(+req: String) -> String:
  +low = String.to_lower(req)
  ok("method=" ++ method.of(req) ++ " auth=" ++ yes(String.contains(low, "\r\nauthorization:")) ++ " ctype=" ++ yes(String.contains(low, "\r\ncontent-type:")))

def answer(+req: String, +other: U32) -> String:
  +t = target.of(req)
  Bool.pick(String, String.eq(t, "/ok"), ok("hello"),
  Bool.pick(String, String.eq(t, "/chunked"), "HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\n\r\n5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n",
  Bool.pick(String, String.eq(t, "/close"), "HTTP/1.1 200 OK\r\n\r\nuntil close",
  Bool.pick(String, String.eq(t, "/missing"), "HTTP/1.1 404 Not Found\r\ncontent-length: 4\r\n\r\nnope",
  Bool.pick(String, String.eq(t, "/same"), moved("302", "/echo"),
  Bool.pick(String, String.eq(t, "/cross"), moved("302", "http://127.0.0.1:" ++ U32.show(other) ++ "/echo"),
  Bool.pick(String, String.eq(t, "/see"), moved("303", "/echo"),
  Bool.pick(String, String.eq(t, "/keep"), moved("307", "/echo"),
  Bool.pick(String, String.eq(t, "/loop"), moved("302", "/loop"),
  Bool.pick(String, String.eq(t, "/echo"), echo(req),
  ok("bye")))))))))))

type Sv is Type:
  Listen{l: Listener}
  Took{l: Listener, r: Result<&1, &1, U32 & String, Socket>}
  Read{l: Listener, r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>}
  Stop{l: Listener}

def sv.took(a: Listener & Result<&1, &1, U32 & String, Socket>) -> Sv:
  (l, r) = a
  Took{l, r}

def sv.next(l: Listener, quit: Bool) -> Sv:
  match quit:
    case True{}:
      Stop{l}
    case False{}:
      Listen{l}

# /stall answers only after the client has given up
def sv.stall(on: Bool) -> IO(Unit):
  match on:
    case True{}:
      IO.sleep(3000)
    case False{}:
      IO.pure(Unit, Unit{})

def sv.close(w: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (s, r) = w
  Socket.close(s)

# one server: accept, read the request, answer, close, until /quit
def sv.go(fuel: Nat, +other: U32, st: Sv) -> IO(Unit):
  match fuel st:
    case 0n Listen{l}:
      Listener.close(l)
    case 0n Took{l, r}:
      Listener.close(l)
    case 0n Read{l, r}:
      Listener.close(l)
    case 0n Stop{l}:
      Listener.close(l)
    case 1n+k Listen{l}:
      IO.bind(Listener & Result<&1, &1, U32 & String, Socket>, Unit, TCP.accept(l), a => sv.go(k, other, sv.took(a)))
    case 1n+k Took{l, Done{s}}:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Unit, Sys.recv(s, 65536, 2000), r => sv.go(k, other, Read{l, r}))
    case 1n+k Took{l, Fail{e}}:
      sv.go(k, other, Listen{l})
    case 1n+k Read{l, (s, Done{bs})}:
      +req = Bytes.to_ascii(bs)
      do IO<Unit>:
        sv.stall(String.eq(target.of(req), "/stall"))
        w : Socket & Result<&1, &1, U32 & String, Unit> <- Sys.send(s, Bytes.of_ascii(answer(req, other)))
        sv.close(w)
        sv.go(k, other, sv.next(l, String.eq(target.of(req), "/quit")))
    case 1n+k Read{l, (s, Fail{e})}:
      do IO<Unit>:
        Socket.close(s)
        sv.go(k, other, Listen{l})
    case 1n+k Stop{l}:
      Listener.close(l)

def serve(+port: U32, +other: U32) -> IO(Unit):
  do IO<Unit>:
    l : Listener <- IO.try(Listener, TCP.listen("127.0.0.1", port))
    ch : Chan(Unit) <- IO.fork(Unit, sv.go(100n, other, Listen{l}))
    return Unit{}

# The client
# ----------

def shown(r: Result<&1, &1, String, Http.Res>) -> String:
  match r:
    case Done{Http.Res{+status, hs, b, u}}:
      U32.show(status) ++ " " ++ Bytes.to_ascii(b)
    case Fail{w}:
      "fail: " ++ w

def url.of(r: Result<&1, &1, String, Http.Res>) -> String:
  match r:
    case Done{Http.Res{status, hs, b, u}}:
      u
    case Fail{w}:
      "fail: " ++ w

def client(+ms: U32) -> Http.Client:
  Http.Client{Http.Ossl{}, Nil{}, ms}

def creds() -> List<&2, Http1.Field()>:
  [("authorization", "token not-a-real-one"), ("content-type", "application/json")]

def get(+port: U32, +path: String) -> IO(Result<&1, &1, String, Http.Res>):
  Http.fetch(client(5000), "GET", "http://127.0.0.1:" ++ U32.show(port) ++ path, creds(), Nil{})

def post(+port: U32, +path: String) -> IO(Result<&1, &1, String, Http.Res>):
  Http.fetch(client(5000), "POST", "http://127.0.0.1:" ++ U32.show(port) ++ path, creds(), Bytes.of_ascii("{}"))

def st.show(st: Http.St) -> String:
  match st:
    case Http.Go{Http.Hop{m, u, hs, b}}:
      "go " ++ m ++ " " ++ u
    case Http.Got{h, u, r}:
      "got"
    case Http.Out{Done{r}}:
      "done"
    case Http.Out{Fail{w}}:
      "fail: " ++ w

# a hop from https to http, judged without a network: refused
def downgrade() -> String:
  st.show(Http.judge(Http.Hop{"GET", "https://a.example/x", Nil{}, Nil{}}, Maybe.default(&2, Url.Url, Url.parse("https://a.example/x"), Url.Url{"", "", 0, ""}),
    Done{Http1.Resp{Http1.Head{302, [("location", "http://a.example/y")]}, Nil{}}}))

def main() -> IO(Unit):
  do IO<Unit>:
    serve(A(), B())
    serve(B(), A())
    IO.sleep(200)
    r1 : Result<&1, &1, String, Http.Res> <- get(A(), "/ok")
    IO.print(T.eq("content-length", shown(r1), "200 hello"))
    r2 : Result<&1, &1, String, Http.Res> <- get(A(), "/chunked")
    IO.print(T.eq("chunked", shown(r2), "200 hello world"))
    r3 : Result<&1, &1, String, Http.Res> <- get(A(), "/close")
    IO.print(T.eq("close-delimited", shown(r3), "200 until close"))
    r4 : Result<&1, &1, String, Http.Res> <- get(A(), "/missing")
    IO.print(T.eq("a 404 is a response", shown(r4), "404 nope"))
    r5 : Result<&1, &1, String, Http.Res> <- get(A(), "/same")
    IO.print(T.eq("same origin keeps the credentials (a 302 drops the body headers)", shown(r5), "200 method=GET auth=yes ctype=no"))
    r6 : Result<&1, &1, String, Http.Res> <- get(A(), "/cross")
    IO.print(T.eq("another origin drops the credentials", shown(r6), "200 method=GET auth=no ctype=no"))
    r7 : Result<&1, &1, String, Http.Res> <- get(A(), "/cross")
    IO.print(T.eq("the final url is the last hop", url.of(r7), "http://127.0.0.1:14812/echo"))
    r8 : Result<&1, &1, String, Http.Res> <- post(A(), "/see")
    IO.print(T.eq("303 after a POST is a GET without the body", shown(r8), "200 method=GET auth=yes ctype=no"))
    r9 : Result<&1, &1, String, Http.Res> <- post(A(), "/keep")
    IO.print(T.eq("307 keeps the POST", shown(r9), "200 method=POST auth=yes ctype=yes"))
    r10 : Result<&1, &1, String, Http.Res> <- get(A(), "/loop")
    IO.print(T.eq("a redirect loop stops", shown(r10), "fail: too many redirects"))
    r11 : Result<&1, &1, String, Http.Res> <- Http.fetch(client(1000), "GET", "http://127.0.0.1:14811/stall", Nil{}, Nil{})
    IO.print(T.eq("a server that never answers times out", shown(r11), "fail: timed out"))
    r12 : Result<&1, &1, String, Http.Res> <- Http.fetch(client(2000), "GET", "http://127.0.0.1:1/", Nil{}, Nil{})
    IO.print(T.ok("a refused port fails", String.starts_with(shown(r12), "fail: can't connect to 127.0.0.1")))
    r13 : Result<&1, &1, String, Http.Res> <- Http.fetch(client(2000), "GET", "ftp://127.0.0.1/", Nil{}, Nil{})
    IO.print(T.eq("only http and https", shown(r13), "fail: not an http or https url: ftp://127.0.0.1/"))
    IO.print(T.eq("https to http is refused", downgrade(), "fail: refused a redirect from https to http"))
    c : Result<&1, &1, U32 & String, Http.Client> <- Http.client(Http.Bend{}, 1000)
    IO.print(T.ok("the bend transport says it isn't wired", Result.is_fail(&1, &1, U32 & String, Http.Client, c)))
    r14 : Result<&1, &1, String, Http.Res> <- get(A(), "/quit")
    r15 : Result<&1, &1, String, Http.Res> <- get(B(), "/quit")
    return Unit{}
