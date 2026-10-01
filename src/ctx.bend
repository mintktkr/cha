# ctx: which forge, host and repo a command talks to, and the token for it.
import Base

type Forge is Data:
  Gitea{}
  GitHub{}

type Repo is Data:
  Repo{forge: Forge, host: String, owner: String, name: String}

# Text
# ----

def first(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{h, t}:
      h

# everything after the first item, joined back with sep
def rest(xs: List<&2, String>, +sep: String) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{h, t}:
      String.join(t, sep)

def last.of(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      ""
    case Some{x}:
      x

def last(xs: List<&2, String>) -> String:
  last.of(List.last(&2, String, xs))

def cut.if(+s: String, +n: Nat, has: Bool) -> String:
  match has:
    case True{}:
      String.drop(s, n)
    case False{}:
      s

def strip_prefix(+s: String, +p: String) -> String:
  cut.if(s, String.length(p), String.starts_with(s, p))

def keep.if(+s: String, +n: Nat, has: Bool) -> String:
  match has:
    case True{}:
      String.take(s, n)
    case False{}:
      s

def strip_suffix(+s: String, +p: String) -> String:
  keep.if(s, Nat.sub(String.length(s), String.length(p)), String.ends_with(s, p))

def or.if(+a: String, +b: String, empty: Bool) -> String:
  match empty:
    case True{}:
      b
    case False{}:
      a

# a, unless it is empty
def or(+a: String, +b: String) -> String:
  or.if(a, b, String.is_empty(a))

# Remotes
# -------

def forge.of(eq: Bool) -> Forge:
  match eq:
    case True{}:
      GitHub{}
    case False{}:
      Gitea{}

def forge(+host: String) -> Forge:
  forge.of(String.eq(host, "github.com"))

# (host, path) of a scheme URL: https://u@host:port/owner/repo
def split.url(+u: String) -> String & String:
  +scheme = first(String.split(u, ':'))
  +tail = String.drop(u, (String.length(scheme) + 3n : Nat))
  +segs = String.split(tail, '/')
  (first(String.split(last(String.split(first(segs), '@')), ':')), rest(segs, "/"))

# (host, path) of an scp-like remote: git@host:owner/repo
def split.scp(+u: String) -> String & String:
  +parts = String.split(u, ':')
  (last(String.split(first(parts), '@')), rest(parts, ":"))

def split.if(+u: String, url: Bool) -> String & String:
  match url:
    case True{}:
      split.url(u)
    case False{}:
      split.scp(u)

def repo.of(+host: String, segs: List<&2, String>) -> Maybe<&2, Repo>:
  match segs:
    case Con{o, Con{n, Nil{}}}:
      Some{Repo{forge(host), host, o, n}}
    case x:
      None{}

def repo.at(hp: String & String) -> Maybe<&2, Repo>:
  (+host, path) = hp
  repo.of(host, String.split(strip_prefix(path, "/"), '/'))

# a remote URL as a repo, in any of git's spellings
def parse_remote(+url: String) -> Maybe<&2, Repo>:
  +u = strip_suffix(strip_suffix(String.trim(url), "/"), ".git")
  repo.at(split.if(u, String.contains(u, "://")))

# Git config
# ----------

type Line is Data:
  Sect{origin: Bool}
  Url{v: String}
  Other{}

def classify.url(+t: String, is_url: Bool) -> Line:
  match is_url:
    case True{}:
      Url{String.trim(rest(String.split(t, '='), "="))}
    case False{}:
      Other{}

def classify.if(+t: String, sect: Bool) -> Line:
  match sect:
    case True{}:
      Sect{String.eq(t, "[remote \"origin\"]")}
    case False{}:
      classify.url(t, String.eq(String.trim(first(String.split(t, '='))), "url"))

def classify(+l: String) -> Line:
  +t = String.trim(l)
  classify.if(t, String.starts_with(t, "["))

def classify.all(ls: List<&2, String>) -> List<&2, Line>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{l, rest}:
      classify(l) <> classify.all(rest)

def find_url(ls: List<&2, Line>, in: Bool) -> String:
  match ls in:
    case Nil{} b:
      ""
    case Con{Sect{o}, rest} b:
      find_url(rest, o)
    case Con{Url{v}, rest} True{}:
      v
    case Con{x, rest} b:
      find_url(rest, b)

# the url of remote "origin" in a git config's text
def origin_url(+cfg: String) -> String:
  find_url(classify.all(String.lines(cfg)), False{})

# Credentials
# -----------

type Cred is Data:
  Cred{user: String, host: String, token: String}
  NoCred{}

# https://user:token@host[/path] from ~/.git-credentials
def cred.of(+auth: String, +loc: String) -> Cred:
  +up = String.split(auth, ':')
  Cred{first(up), first(String.split(loc, '/')), rest(up, ":")}

def cred.split(+tail: String, ok: Bool) -> Cred:
  match ok:
    case True{}:
      cred.of(first(String.split(tail, '@')), last(String.split(tail, '@')))
    case False{}:
      NoCred{}

def cred.parse(+l: String) -> Cred:
  +t = String.trim(l)
  +tail = String.drop(t, (String.length(first(String.split(t, ':'))) + 3n : Nat))
  cred.split(tail, String.contains(t, "://") && String.contains(tail, "@"))

def cred.keep.if(c: Cred, ok: Bool) -> Cred:
  match ok:
    case True{}:
      c
    case False{}:
      NoCred{}

# c, when it is for host and (if user isn't empty) for user
def cred.keep(c: Cred, +host: String, +user: String) -> Cred:
  match c:
    case NoCred{}:
      NoCred{}
    case Cred{+u, +h, +t}:
      cred.keep.if(Cred{u, h, t}, String.eq(h, host) && (String.is_empty(user) || String.eq(u, user)))

def cred.scan.at(c: Cred, +later: String) -> String:
  match c:
    case Cred{u, h, t}:
      t
    case NoCred{}:
      later

def cred.scan(ls: List<&2, String>, +host: String, +user: String) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{l, rest}:
      cred.scan.at(cred.keep(cred.parse(l), host, user), cred.scan(rest, host, user))

# the token for host in a git-credentials text, "" when none
def token_in(+creds: String, +host: String, +user: String) -> String:
  cred.scan(String.lines(creds), host, user)

# IO
# --

def env.got(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Done{s}:
      s
    case Fail{e}:
      ""

# an environment variable, "" when unset
def env(name: String) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
    return env.got(r)

def slurp.text(f: File, got: Result<&1, &1, U32 & String, String>) -> IO(String):
  do IO<String>:
    File.close(f)
    return env.got(got)

def slurp.done(r: File & Result<&1, &1, U32 & String, String>) -> IO(String):
  (f, got) = r
  slurp.text(f, got)

def slurp.open(r: Result<&1, &1, U32 & String, File>) -> IO(String):
  match r:
    case Done{f}:
      do IO<String>:
        got : File & Result<&1, &1, U32 & String, String> <- File.read(f, 1048576)
        slurp.done(got)
    case Fail{e}:
      IO.pure(String, "")

# a file's text, "" when it can't be read
def slurp(path: String) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    slurp.open(r)

# the directory a .git file points at, relative paths taken from dir
def gitdir.of(+dir: String, +gd: String) -> String:
  or.if(gd, dir ++ gd, Bool.not(String.starts_with(gd, "/")))

def common.of(+gd: String, +cd: String) -> String:
  or.if(gd ++ "/" ++ cd, gd, String.is_empty(cd))

# a worktree's config: <gitdir>/<commondir>/config
def worktree.cfg(+dir: String, +dotgit: String, has: Bool) -> IO(String):
  match has:
    case True{}:
      do IO<String>:
        +gd : String = gitdir.of(dir, String.trim(String.drop(dotgit, 8n)))
        cd : String <- slurp(gd ++ "/commondir")
        slurp(common.of(gd, String.trim(cd)) ++ "/config")
    case False{}:
      IO.pure(String, "")

def at_dir.pick(+dir: String, +cfg: String, empty: Bool) -> IO(String):
  match empty:
    case True{}:
      do IO<String>:
        +dotgit : String <- slurp(dir ++ ".git")
        worktree.cfg(dir, dotgit, String.starts_with(dotgit, "gitdir: "))
    case False{}:
      IO.pure(String, cfg)

# the git config of the checkout rooted at dir, "" when there is none
def at_dir(+dir: String) -> IO(String):
  do IO<String>:
    +cfg : String <- slurp(dir ++ ".git/config")
    at_dir.pick(dir, cfg, String.is_empty(cfg))

def ups(n: Nat, +p: String) -> List<&2, String>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      p <> ups(k, p ++ "../")

def scan(ps: List<&2, String>) -> IO(String):
  match ps:
    case Nil{}:
      IO.pure(String, "")
    case Con{p, rest}:
      do IO<String>:
        +here : String <- at_dir(p)
        +later : String <- scan(rest)
        return or(here, later)

# the git config of the checkout around the current directory, nearest first
def git_config() -> IO(String):
  scan(ups(12n, ""))

def flag.repo.of(+r: String, segs: List<&2, String>, cur: Maybe<&2, Repo>) -> Maybe<&2, Repo>:
  match segs cur:
    case Con{+h, Con{o, Con{n, Nil{}}}} c:
      Some{Repo{forge(h), h, o, n}}
    case Con{o, Con{n, Nil{}}} Some{Repo{f, h, x, y}}:
      Some{Repo{f, h, o, n}}
    case s c:
      None{}

# the repo named by -R: owner/repo on the current host, or host/owner/repo
def flag.repo(+r: String, +cur: Maybe<&2, Repo>) -> Maybe<&2, Repo>:
  flag.repo.of(r, String.split(r, '/'), cur)

# the token for repo: CHA_TOKEN, then GITHUB_TOKEN / GH_TOKEN on github,
# then ~/.git-credentials (CHA_USER picks the user when a host has several)
def token.creds(+host: String, +user: String, +home: String) -> IO(String):
  do IO<String>:
    +creds : String <- slurp(home ++ "/.git-credentials")
    return token_in(creds, host, user)

def token.github(f: Forge) -> IO(String):
  match f:
    case GitHub{}:
      do IO<String>:
        +a : String <- env("GITHUB_TOKEN")
        +b : String <- env("GH_TOKEN")
        return or(a, b)
    case Gitea{}:
      IO.pure(String, "")

def token(+repo: Repo) -> IO(String):
  match repo:
    case Repo{+f, +h, o, n}:
      do IO<String>:
        +t1 : String <- env("CHA_TOKEN")
        +t2 : String <- token.github(f)
        +user : String <- env("CHA_USER")
        +home : String <- env("HOME")
        +t3 : String <- token.creds(h, user, home)
        return or(t1, or(t2, t3))
