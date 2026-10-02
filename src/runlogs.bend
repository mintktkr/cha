# Pure Actions log selection. Gitea exposes step times, not per-step log offsets.
import Base
import ./api.bend as Api
import ./ctx.bend as Ctx
import 0x3bfb4ae4d3b87b90f01bfcd298211455/time.bend as Time

type Step is Data:
  Step{position: U32, name: String, status: String, conclusion: String, started: String, completed: String}

def same(+a: String, +b: String) -> Bool:
  String.eq(String.to_lower(a), String.to_lower(b))

def strip.bom.if(+text: String, bom: Bool) -> String:
  match bom:
    case True{}:
      String.drop(text, 1n)
    case False{}:
      text

# Only the first code point is a transport BOM; interior U+FEFF is log content.
def strip.bom(+text: String) -> String:
  strip.bom.if(text, String.starts_with(text, "\u{feff}"))

def steps.keep(+s: Step, rest: List<&2, Step>, keep: Bool) -> List<&2, Step>:
  match keep:
    case True{}:
      s <> rest
    case False{}:
      rest

# Position is the zero-based position in the job, as GitHub's step-logs API asks
# for; API step.number can have gaps after post steps and must not be decremented.
def steps.go(n: Nat, +i: U32, +src: Map<&2, String>, +root: String, +want: String) -> List<&2, Step>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +prefix = root ++ "." ++ U32.show(i)
      +name = Api.f(src, Api.key(prefix, "name"))
      steps.keep(Step{i, name, Api.f(src, Api.key(prefix, "status")), Api.f(src, Api.key(prefix, "conclusion")), Api.f(src, Api.key(prefix, "started_at")), Api.f(src, Api.key(prefix, "completed_at"))}, steps.go(p, (i + 1 : U32), src, root, want), String.is_empty(want) || same(name, want))

def steps.of(+src: Map<&2, String>, +root: String, +want: String) -> List<&2, Step>:
  steps.go(Api.count(src, root), 0, src, root, want)

def steps.names(xs: List<&2, Step>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{Step{i, name, status, conclusion, a, b}, rest}:
      "  " ++ name ++ "\n" ++ steps.names(rest)

def at.least(c: Cmp) -> Bool:
  match c:
    case LT{}:
      False{}
    case x:
      True{}

def at.most(c: Cmp) -> Bool:
  match c:
    case GT{}:
      False{}
    case x:
      True{}

def after(c: Cmp) -> Bool:
  match c:
    case GT{}:
      True{}
    case x:
      False{}

def whole(i: Time.Instant) -> Time.Instant:
  match i:
    case Time.Instant{s, n}:
      Time.Instant{s, 0}

# Gitea stores step start/stop in whole seconds. Keep the entire final second so
# the selected step's last lines are not lost. Adjacent steps may share a second;
# the caller reports this precision limit instead of guessing runner markers.
def line.in(m: Maybe<&2, Time.Instant>, +start: Time.Instant, +stop: Time.Instant) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{i}:
      +t = whole(i)
      at.least(Time.Instant.cmp(t, start)) && at.most(Time.Instant.cmp(t, stop))

def line.keep(+line: String, rest: String, keep: Bool) -> String:
  match keep:
    case True{}:
      line ++ "\n" ++ rest
    case False{}:
      rest

def lines(xs: List<&2, String>, +start: Time.Instant, +stop: Time.Instant) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+line, rest}:
      line.keep(line, lines(rest, start, stop), line.in(Time.rfc3339.parse(Ctx.first(String.split(line, ' '))), start, stop))

def window.valid(+text: String, +start: Time.Instant, +stop: Time.Instant, valid: Bool) -> Maybe<&2, String>:
  match valid:
    case False{}:
      None{}
    case True{}:
      Some{lines(String.split(strip.bom(text), '\n'), whole(start), whole(stop))}

def window.parsed(+text: String, start: Maybe<&2, Time.Instant>, stop: Maybe<&2, Time.Instant>) -> Maybe<&2, String>:
  match start stop:
    case Some{+a} Some{+b}:
      window.valid(text, a, b, after(Time.Instant.cmp(a, Time.Instant.epoch())) && at.least(Time.Instant.cmp(b, a)))
    case _ _:
      None{}

def window(+text: String, +start: String, +stop: String) -> Maybe<&2, String>:
  window.parsed(text, Time.rfc3339.parse(start), Time.rfc3339.parse(stop))
