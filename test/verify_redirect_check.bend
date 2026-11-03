# offline checks for the redirect rules verify/redirect/Redirect.tla models: the hops the
# model walks, judged one at a time through http.bend's judge and hop.bend's rules. judge is
# pure, so this needs no network. scripts/check.sh runs it with the other *_check.bend.
import Base
import ../lib/chaki/check.bend as T
import ../lib/chaki/hop.bend as Hop
import ../lib/chaki/http.bend as Http
import ../lib/chaki/http1.bend as Http1
import ../lib/chaki/url.bend as Url

# the caller's headers: the two hop.bend's judge.go may drop, and nothing else
def creds() -> List<&2, Http1.Field()>:
  [("authorization", "token not-a-real-one"), ("cookie", "session=1")]

def resp(+code: U32, +loc: String) -> Http1.Resp:
  Http1.Resp{Http1.Head{code, [("location", loc)]}, Nil{}}

# the header names of a hop, in the order the chain carries them
def names.go(hs: List<&2, Http1.Field()>, acc: String) -> String:
  match hs:
    case Nil{}:
      acc
    case Con{(+k, +v), t}:
      names.go(t, acc ++ k ++ " ")

def hop.show(h: Hop.Hop) -> String:
  match h:
    case Hop.Hop{m, u, hs, b}:
      m ++ " " ++ u ++ " [" ++ names.go(hs, "") ++ "]"

# the hop in flight is answered with a 302 to loc, so judge hands back the next hop (Http.Go)
# or the reason the chain stops (Http.Out)
def judge.at(h: Hop.Hop, +loc: String, m: Maybe<&2, Url.Url>) -> Http.St:
  match m:
    case None{}:
      Http.Out{Fail{"not a url"}}
    case Some{+from}:
      Http.judge(h, from, Done{resp(302, loc)})

def judge.next(h: Hop.Hop, +loc: String) -> Http.St:
  Hop.Hop{+m, +u, +hs, +b} = h
  judge.at(Hop.Hop{m, u, hs, b}, loc, Url.parse(u))

def st.show(st: Http.St) -> String:
  match st:
    case Http.Go{h}:
      hop.show(h)
    case Http.Got{h, u, r}:
      hop.show(h)
    case Http.Out{Done{r}}:
      Http.Res{status, headers, body, url} = r
      "done " ++ U32.show(status)
    case Http.Out{Fail{w}}:
      "fail: " ++ w

def next.hop(st: Http.St) -> Hop.Hop:
  match st:
    case Http.Go{h}:
      h
    case Http.Got{h, u, r}:
      h
    case Http.Out{Done{r}}:
      Hop.Hop{"", "", Nil{}, Nil{}}
    case Http.Out{Fail{w}}:
      Hop.Hop{"", "", Nil{}, Nil{}}

# a request with no body: what every hop in the model's walk carries
def hop.of(+method: String, +url: String, +hs: List<&2, Http1.Field()>) -> Hop.Hop:
  Hop.Hop{method, url, hs, Nil{}}

# one hop of a chain: the Location the answer named, and the hop judge makes of it
def walk.step(h: Hop.Hop, +loc: String) -> Hop.Hop:
  next.hop(judge.next(h, loc))

def run() -> List<&2, String>:
  +first = hop.of("GET", "https://a.example/x", creds())
  +second = walk.step(first, "https://b.example/y")
  third = walk.step(second, "https://a.example/z")
  +within = hop.of("GET", "https://a.example/x", creds())
  here = walk.step(within, "https://a.example/y")
  down = hop.of("GET", "https://a.example/x", creds())
  refused = judge.next(down, "http://b.example/y")
  [T.eq("hop 1 carries the caller's credentials", hop.show(first), "GET https://a.example/x [authorization cookie ]"),
    T.eq("hop 2 to the other origin drops them", hop.show(second), "GET https://b.example/y []"),
    T.eq("hop 3 back at the first origin keeps them dropped", hop.show(third), "GET https://a.example/z []"),
    T.eq("a redirect within the origin keeps them", hop.show(here), "GET https://a.example/y [authorization cookie ]"),
    T.eq("a redirect from https to http is refused", st.show(refused), "fail: refused a redirect from https to http")]

def print.all(xs: List<&2, String>) -> IO(Unit):
  match xs:
    case Nil{}:
      do IO<Unit>:
        return Unit{}
    case l <> t:
      do IO<Unit>:
        IO.print(l)
        print.all(t)

def main() -> IO(Unit):
  print.all(run())
