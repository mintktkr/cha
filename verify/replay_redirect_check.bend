# replay_check: the redirect rules of lib/chaki/http.bend judged one hop at a time, the same
# hops Redirect.tla walks. http.bend's judge is pure, so this needs no network.
#   rr bend verify/replay_redirect_check.bend
# Each line says what the code does; a FAIL line means the code disagrees with the model.
import Base
import ../lib/chaki/check.bend as T
import ../lib/chaki/http.bend as Http
import ../lib/chaki/http1.bend as Http1
import ../lib/chaki/url.bend as Url

# the caller's headers: the two judge.go may drop, and nothing else
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

def hop.show(h: Http.Hop) -> String:
  match h:
    case Http.Hop{m, u, hs, b}:
      m ++ " " ++ u ++ " [" ++ names.go(hs, "") ++ "]"

# judge.go: the hop in flight is answered with a redirect to loc, so judge returns the next
# hop (Http.Go) or the reason the chain stops (Http.Out)
def judge.next(h: Http.Hop, +loc: String) -> Http.St:
  Http.Hop{+m, +u, +hs, +b} = h
  match Url.parse(u):
    case None{}:
      Http.Out{Fail{"not a url"}}
    case Some{+from}:
      Http.judge(Http.Hop{m, u, hs, b}, from, Done{resp(302, loc)})

def st.show(st: Http.St) -> String:
  match st:
    case Http.Go{h}:
      hop.show(h)
    case Http.Got{h, u, r}:
      hop.show(h)
    case Http.Out{Done{r}}:
      "done " ++ U32.show(r.status)
    case Http.Out{Fail{w}}:
      "fail: " ++ w

def next.hop(st: Http.St) -> Http.Hop:
  match st:
    case Http.Go{h}:
      h
    case Http.Got{h, u, r}:
      h
    case Http.Out{Done{r}}:
      Http.Hop{"", "", Nil{}, Nil{}}
    case Http.Out{Fail{w}}:
      Http.Hop{"", "", Nil{}, Nil{}}

def run() -> List<&2, String>:
  h1 = Http.Hop{"GET", "https://a.example/x", creds(), Nil{}}
  s2 = judge.next(h1, "https://b.example/y")
  s3 = judge.next(next.hop(s2), "https://a.example/z")
  s4 = judge.next(Http.Hop{"GET", "https://a.example/x", creds(), Nil{}}, "https://a.example/y")
  s5 = judge.next(Http.Hop{"GET", "https://a.example/x", creds(), Nil{}}, "http://b.example/y")
  [T.eq("hop 1 carries the caller's credentials", hop.show(h1), "GET https://a.example/x [authorization cookie ]"),
    T.eq("hop 2 to the other origin drops them", st.show(s2), "GET https://b.example/y []"),
    T.eq("hop 3 back at the first origin keeps them dropped", st.show(s3), "GET https://a.example/z []"),
    T.eq("a redirect within the origin keeps them", st.show(s4), "GET https://a.example/y [authorization cookie ]"),
    T.eq("a redirect from https to http is refused", st.show(s5), "fail: refused a redirect from https to http")]

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
