# Pure Actions log selection: GitHub's job log is cut by the runner's group markers,
# Gitea's by the step times it exposes instead of per-step log offsets.
import Base
import ./api.bend as Api
import ./ctx.bend as Ctx
import 0x3bfb4ae4d3b87b90f01bfcd298211455/time.bend as Time
import 0x4eed9d7ac6ece61523d747a9d804e4f0/int.bend as Int

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

# Lines of a log. Base's String.split recurses once per character and overflows the
# stack on a job log of a few dozen KB, so this one walks the text as a tail call:
# the current line is held reversed, and finished lines pile up in reverse.
def split.close(st: String & List<&2, String>) -> String & List<&2, String>:
  (line, acc) = st
  (SNil{}, String.reverse(line) <> acc)

def split.push(+c: U32, st: String & List<&2, String>) -> String & List<&2, String>:
  (line, acc) = st
  (SCon{Chr{c}, line}, acc)

def split.step(+c: U32, st: String & List<&2, String>, nl: Bool) -> String & List<&2, String>:
  match nl:
    case True{}:
      split.close(st)
    case False{}:
      split.push(c, st)

def split.end(st: String & List<&2, String>) -> List<&2, String>:
  (line, acc) = st
  List.reverse(&2, String, String.reverse(line) <> acc)

def split.go(s: String, st: String & List<&2, String>) -> List<&2, String>:
  match s:
    case SNil{}:
      split.end(st)
    case SCon{Chr{+c}, t}:
      split.go(t, split.step(c, st, U32.is_eq(c, 10)))

def split.lines(text: String) -> List<&2, String>:
  split.go(text, (SNil{}, Nil{}))

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
      Some{lines(split.lines(strip.bom(text)), whole(start), whole(stop))}

def window.parsed(+text: String, start: Maybe<&2, Time.Instant>, stop: Maybe<&2, Time.Instant>) -> Maybe<&2, String>:
  match start stop:
    case Some{+a} Some{+b}:
      window.valid(text, a, b, after(Time.Instant.cmp(a, Time.Instant.epoch())) && at.least(Time.Instant.cmp(b, a)))
    case _ _:
      None{}

def window(+text: String, +start: String, +stop: String) -> Maybe<&2, String>:
  window.parsed(text, Time.rfc3339.parse(start), Time.rfc3339.parse(stop))


# GitHub
# ------
# GitHub answers 404 for every per-step log index, so a step's log comes out of the
# job's one stream: the runner opens each step it runs with a "##[group]Run ..." line
# and the next step's line ends its section. A composite action's inner groups look
# exactly like a step's own, so every line is matched against the job's step list: the
# step the group text names first, then the step whose second the line opens, then the
# first step whose window holds it.

# where a cut is: reading the next line, or holding the section it has collected
type Cut is Type:
  More{lines: List<&2, String>, waiting: List<&2, Step>, open: Bool, acc: List<&2, String>}
  Closed{acc: List<&2, String>}

# A log line without the timestamp the runner prefixes it with.
def group.body(+line: String) -> String:
  String.drop(line, (String.length(Ctx.first(String.split(line, ' '))) + 1n : Nat))

# The line that opens a step's section.
def group.line(+line: String) -> Bool:
  String.starts_with(group.body(line), "##[group]Run ")

# What the runner wrote after "##[group]Run ": a command, or an action reference.
def group.text(+line: String) -> String:
  String.drop(group.body(line), 13n)

# What the runner writes before the post steps, which end the run's steps.
def post.line(+line: String) -> Bool:
  String.eq(group.body(line), "Post job cleanup.")

# The runner's own steps (setup, post actions, teardown) never open a group.
def runner.step(+name: String) -> Bool:
  String.eq(name, "Set up job") || (String.eq(name, "Complete job") || String.starts_with(name, "Post "))

# A step opens a section when it ran: the forge timed it, it was not skipped and the
# runner did not write it.
def step.opens(+s: Step) -> Bool:
  match s:
    case Step{p, name, status, conclusion, started, completed}:
      +ran = Bool.not(String.eq(conclusion, "skipped"))
      +timed = Bool.and(Bool.not(String.is_empty(started)), Bool.not(String.is_empty(completed)))
      Bool.and(ran, Bool.and(timed, Bool.not(runner.step(name))))

def waiting.keep(+head: Step, +rest: List<&2, Step>, keep: Bool) -> List<&2, Step>:
  match keep:
    case True{}:
      head <> rest
    case False{}:
      rest

# The steps that can own a section, in job order.
def waiting.of(+steps: List<&2, Step>) -> List<&2, Step>:
  match steps:
    case Nil{}:
      Nil{}
    case Con{+head, +rest}:
      waiting.keep(head, waiting.of(rest), step.opens(head))

# An unnamed run or uses step is named after what it runs: "Run <group text>".
def step.named(+s: Step, +text: String) -> Bool:
  match s:
    case Step{p, +name, status, conclusion, started, completed}:
      same(name, "Run " ++ text)

def step.position(+s: Step) -> U32:
  match s:
    case Step{position, n, status, conclusion, started, completed}:
      position

# A stamp the forge did not give lands on the epoch, which no log line reaches.
def stamp(m: Maybe<&2, Time.Instant>) -> Time.Instant:
  Maybe.default(&2, Time.Instant, m, Time.Instant.epoch())

# A stamp as whole seconds since the epoch, the grain the forge times a step with; 0 when
# the forge gave none. Windows compare these U32s, not Instants: an Instant is wide on the
# native lane, and a def holding four of them is past its 247-word limit.
def secs(i: Time.Instant) -> U32:
  match i:
    case Time.Instant{s, n}:
      Int.I64.to_u32(s)

def second.of(+s: String) -> U32:
  secs(stamp(Time.rfc3339.parse(s)))

# A log line's time, as a whole second.
def line.second(+line: String) -> U32:
  second.of(Ctx.first(String.split(line, ' ')))

def in.window.at(+t: U32, +start: U32, +stop: U32) -> Bool:
  U32.is_gt(start, 0) && (U32.is_ge(t, start) && U32.is_le(t, stop))

# The line's second against the step's window, which is as fine as the forge's times.
def in.window(+line: String, +s: Step) -> Bool:
  match s:
    case Step{p, n, status, conclusion, +started, +completed}:
      in.window.at(line.second(line), second.of(started), second.of(completed))

# The line opens the step's window when the two whole seconds agree.
def at.start(+line: String, +s: Step) -> Bool:
  match s:
    case Step{p, n, status, conclusion, +started, +completed}:
      in.window.at(line.second(line), second.of(started), second.of(started))

# scrutinees follow binder order, so edge comes before owns here
def owner.rank.at(+line: String, +head: Step, edge: Bool, owns: Bool) -> Nat:
  match edge owns:
    case _ True{}:
      3n
    case True{} False{}:
      2n
    case False{} False{}:
      1n

# 3 when the group text is the step's own name, 2 when the line opens its window,
# 1 when the window only holds it, 0 when the step has nothing to do with the line.
def owner.rank(+line: String, +text: String, +head: Step, inside: Bool) -> Nat:
  match inside:
    case False{}:
      0n
    case True{}:
      owner.rank.at(line, head, at.start(line, head), step.named(head, text))

def owner.max.rank(+rank: Nat, +line: String, +text: String, +head: Step) -> Nat:
  Nat.max(rank, owner.rank(line, text, head, in.window(line, head)))

def owner.better(+line: String, +text: String, +head: Step, +rank: Nat) -> Bool:
  Nat.is_gt(owner.rank(line, text, head, in.window(line, head)), rank)

def owner.pick(+head: Step, +best: Maybe<&2, Step>, better: Bool) -> Maybe<&2, Step>:
  match better:
    case True{}:
      Some{head}
    case False{}:
      best

# The step a group line belongs to: the highest rank wins and the job's order breaks a
# tie, so an inner group goes to a step still waiting rather than to one that already
# has its section.
def owner.take(+line: String, +text: String, +waiting: List<&2, Step>, +rank: Nat, +best: Maybe<&2, Step>) -> Maybe<&2, Step>:
  match waiting:
    case Nil{}:
      best
    case Con{+head, +rest}:
      owner.take(line, text, rest, owner.max.rank(rank, line, text, head), owner.pick(head, best, owner.better(line, text, head, rank)))

def owner.drop(+head: Step, +rest: List<&2, Step>, +tail: List<&2, Step>, hit: Bool) -> List<&2, Step>:
  match hit:
    case True{}:
      rest
    case False{}:
      head <> tail

def owner.without(+position: U32, +waiting: List<&2, Step>) -> List<&2, Step>:
  match waiting:
    case Nil{}:
      Nil{}
    case Con{+head, +rest}:
      owner.drop(head, rest, owner.without(position, rest), U32.is_eq(step.position(head), position))

def owner.done(+line: String, +waiting: List<&2, Step>, m: Maybe<&2, Step>) -> Maybe<&2, Step> & List<&2, Step>:
  match m:
    case None{}:
      (None{}, waiting)
    case Some{+s}:
      (Some{s}, owner.without(step.position(s), waiting))

# The owner of a group line, and the waiting list without it.
def owner(+line: String, +waiting: List<&2, Step>) -> Maybe<&2, Step> & List<&2, Step>:
  owner.done(line, waiting, owner.take(line, group.text(line), waiting, 0n, None{}))

def cut.text(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+head, Nil{}}:
      head
    case Con{+head, +rest}:
      head ++ "\n" ++ cut.text(rest)

def cut.some(+open: Bool, +acc: List<&2, String>) -> Maybe<&2, String>:
  match open:
    case True{}:
      Some{cut.text(List.reverse(&2, String, acc))}
    case False{}:
      None{}

def cut.end(s: Cut) -> Maybe<&2, String>:
  match s:
    case Closed{acc}:
      Some{cut.text(List.reverse(&2, String, acc))}
    case More{l, w, open, acc}:
      cut.some(open, acc)

def cut.content.at(+line: String, +rest: List<&2, String>, +waiting: List<&2, Step>, +acc: List<&2, String>, post: Bool) -> Cut:
  match post:
    case True{}:
      Closed{acc}
    case False{}:
      More{rest, waiting, True{}, line <> acc}

def cut.content(+line: String, +rest: List<&2, String>, +waiting: List<&2, Step>, +open: Bool, +acc: List<&2, String>) -> Cut:
  match open:
    case False{}:
      More{rest, waiting, False{}, acc}
    case True{}:
      cut.content.at(line, rest, waiting, acc, post.line(line))

def cut.claim(+line: String, +rest: List<&2, String>, +left: List<&2, Step>, +open: Bool, +acc: List<&2, String>, mine: Bool) -> Cut:
  match open mine:
    case False{} True{}:
      More{rest, left, True{}, line <> acc}
    case True{} _:
      Closed{acc}
    case False{} False{}:
      More{rest, left, False{}, acc}

def cut.own.at(+target: U32, +line: String, +rest: List<&2, String>, +waiting: List<&2, Step>, +left: List<&2, Step>, +open: Bool, +acc: List<&2, String>, m: Maybe<&2, Step>) -> Cut:
  match m:
    case None{}:
      cut.content(line, rest, waiting, open, acc)
    case Some{s}:
      cut.claim(line, rest, left, open, acc, U32.is_eq(step.position(s), target))

# a group line no waiting step owns is content like any other
def cut.own(+target: U32, +line: String, +rest: List<&2, String>, +waiting: List<&2, Step>, +open: Bool, +acc: List<&2, String>, r: Maybe<&2, Step> & List<&2, Step>) -> Cut:
  (m, +left) = r
  cut.own.at(target, line, rest, waiting, left, open, acc, m)

def cut.line(+target: U32, +line: String, +rest: List<&2, String>, +waiting: List<&2, Step>, +open: Bool, +acc: List<&2, String>, group: Bool) -> Cut:
  match group:
    case False{}:
      cut.content(line, rest, waiting, open, acc)
    case True{}:
      cut.own(target, line, rest, waiting, open, acc, owner(line, waiting))

# One line per step of fuel. A section ends at the next step's group line, or at the
# line the runner closes the run steps with.
def cut.go(fuel: Nat, +target: U32, st: Cut) -> Maybe<&2, String>:
  match fuel st:
    case 0n s:
      cut.end(s)
    case 1n+p More{Con{+line, +rest}, w, open, acc}:
      cut.go(p, target, cut.line(target, line, rest, w, open, acc, group.line(line)))
    case 1n+p More{Nil{}, w, open, acc}:
      cut.end(More{Nil{}, w, open, acc})
    case 1n+p Closed{acc}:
      Some{cut.text(List.reverse(&2, String, acc))}

# One step's section of a job log, or none when the log never opened it.
def cut.section(+text: String, +steps: List<&2, Step>, +position: U32) -> Maybe<&2, String>:
  +lines = split.lines(strip.bom(text))
  cut.go(Nat.add(List.length(&2, String, lines), 1n), position, More{lines, waiting.of(steps), False{}, Nil{}})
