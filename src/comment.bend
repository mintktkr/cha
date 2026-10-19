# comment: editing and deleting a conversation comment. On Gitea, Forgejo and GitHub a
# pull request's conversation comments are the issue's comments, so issue and pr share
# this file: one endpoint, PATCH to edit and DELETE to remove.
import Base
import 0x584fc27920487ceab242392391418d7f/json.bend as Json
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
import ./ctx.bend as Ctx
import ./api.bend as Api
import ./ui.bend as Ui
import ./cli.bend as Cli

# ids
# ---

# ASCII '0' to '9'
def digit.ok(+c: U32) -> Bool:
  Bool.and(U32.is_le(48, c), U32.is_le(c, 57))

def digits(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{+c}, t}:
      Bool.and(digit.ok(c), digits(t))

# a comment id is a number: it becomes a path segment, so only digits may pass (U32.read
# alone takes some punctuation as a zero, which would leave a ".." in the path)
def id.ok(+raw: String) -> Bool:
  digits(raw) && Bool.not(String.is_empty(raw))

def id.empty.msg(+what: String) -> String:
  what ++ ": give a comment id"

def id.bad.msg(+what: String, +raw: String) -> String:
  what ++ ": expected a comment id, got '" ++ raw ++ "'"

def id.bad.if(+env: Cli.Env, +what: String, +raw: String, bad: Bool) -> IO(String):
  match bad:
    case True{}:
      Cli.fail(String, env, id.bad.msg(what, raw))
    case False{}:
      IO.pure(String, raw)

def id.need.if(+env: Cli.Env, +what: String, +raw: String, empty: Bool) -> IO(String):
  match empty:
    case True{}:
      Cli.fail(String, env, id.empty.msg(what))
    case False{}:
      id.bad.if(env, what, raw, Bool.not(id.ok(raw)))

def id.need(+env: Cli.Env, +raw: String, +what: String) -> IO(String):
  id.need.if(env, what, raw, String.is_empty(raw))

# requests
# --------

# a comment's endpoint: the same on both forges, and the same for an issue's comment and a
# pull request's conversation comment
def path(+repo: Ctx.Repo, +id: String) -> String:
  Api.path(repo, "issues/comments/" ++ id)

# an edit's body: the comment as it should read now
def edit.body(+body: String) -> Json.Val:
  Json.Obj{[(Json.utf8("body"), Api.utf8(body))]}

# the edited comment's url, or the forge's error
def edit.if(+env: Cli.Env, body: Bytes.Bytes, +status: U32, good: Bool) -> IO(Unit):
  match good:
    case True{}:
      IO.print(Api.f(Api.obj(body), "html_url"))
    case False{}:
      Cli.fail(Unit, env, Api.message(status, body))

def edit.got(+env: Cli.Env, r: Api.Reply) -> IO(Unit):
  match r:
    case Api.Broke{w}:
      Cli.fail(Unit, env, w)
    case Api.Reply{+status, next, body}:
      edit.if(env, body, status, Api.ok(status))

def edit(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +id: String, +body: String) -> IO(Unit):
  do IO<Unit>:
    r : Api.Reply <- Api.send(repo, tok, "PATCH", path(repo, id), Some{edit.body(body)})
    edit.got(env, r)

# a delete answers no item, so it prints nothing: exit 0 is the receipt
def delete.if(+env: Cli.Env, body: Bytes.Bytes, +status: U32, good: Bool) -> IO(Unit):
  match good:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      Cli.fail(Unit, env, Api.message(status, body))

def delete.got(+env: Cli.Env, r: Api.Reply) -> IO(Unit):
  match r:
    case Api.Broke{w}:
      Cli.fail(Unit, env, w)
    case Api.Reply{+status, next, body}:
      delete.if(env, body, status, Api.ok(status))

def delete(+env: Cli.Env, +repo: Ctx.Repo, +tok: String, +id: String) -> IO(Unit):
  do IO<Unit>:
    r : Api.Reply <- Api.send(repo, tok, "DELETE", path(repo, id), None{})
    delete.got(env, r)

# deleting is forever: off a terminal, --yes has to say someone meant it. cha's one
# terminal check is stdout (Ui.tty); an agent or a CI job has no terminal on either end.
def yes.ok(yes: Bool, tty: Bool) -> Bool:
  match yes:
    case True{}:
      True{}
    case False{}:
      tty

def yes.need.if(+env: Cli.Env, +what: String, missing: Bool) -> IO(Unit):
  match missing:
    case True{}:
      Cli.fail(Unit, env, what ++ ": --yes is required when cha isn't on a terminal")
    case False{}:
      IO.pure(Unit, Unit{})

def yes.need(+env: Cli.Env, yes: Bool, +what: String) -> IO(Unit):
  do IO<Unit>:
    tty : Bool <- Ui.tty()
    yes.need.if(env, what, Bool.not(yes.ok(yes, tty)))
