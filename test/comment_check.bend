# offline checks for the shared comment pieces: the endpoint an edit and a delete use on
# both forges, the edit's JSON body, the id that goes into the path, and the --yes refusal
import Base
import ../lib/chaki/json.bend as Json
import ../lib/chaki/utf8.bend as Utf8
import ../src/ctx.bend as Ctx
import ../src/api.bend as Api
import ../src/comment.bend as Comment

def gitea() -> Ctx.Repo:
  Ctx.Repo{Ctx.Gitea{}, "tea.example.org", "memu", "sandbox"}

def github() -> Ctx.Repo:
  Ctx.Repo{Ctx.GitHub{}, "github.com", "memu", "sandbox"}

def y(x: Bool) -> String:
  String.to_lower(Bool.show(x))

# an edit's body as the forge would read it back
def body.of(+s: String) -> String:
  Api.raw.f(Api.obj(Utf8.encode(Json.encode(Comment.edit.body(s)))), "body")

def report.if(good: Bool, +name: String, +got: String, +want: String) -> String:
  match good:
    case True{}:
      "ok   " ++ name
    case False{}:
      "FAIL " ++ name ++ ": got [" ++ got ++ "], want [" ++ want ++ "]"

def report(good: Bool, +name: String, +got: String, +want: String) -> String:
  report.if(good, name, got, want)

def check(+name: String, +got: String, +want: String) -> String:
  report(String.eq(got, want), name, got, want)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(check("path gitea", Comment.path(gitea(), "1337"), "repos/memu/sandbox/issues/comments/1337"))
    IO.print(check("path github", Comment.path(github(), "1337"), "repos/memu/sandbox/issues/comments/1337"))
    IO.print(check("edit.body carries the body", body.of("boil water first"), "boil water first"))
    IO.print(check("edit.body keeps a quote and a newline", body.of("a \"quoted\" line\nsecond"), "a \"quoted\" line\nsecond"))
    IO.print(check("id.ok on digits", y(Comment.id.ok("1337")), "true"))
    IO.print(check("id.ok rejects a letter", y(Comment.id.ok("13a")), "false"))
    IO.print(check("id.ok rejects a path", y(Comment.id.ok("../labels")), "false"))
    IO.print(check("id.ok rejects dots", y(Comment.id.ok("..")), "false"))
    IO.print(check("id.ok rejects a space", y(Comment.id.ok("1 2")), "false"))
    IO.print(check("id.ok rejects nothing", y(Comment.id.ok("")), "false"))
    IO.print(check("id.empty.msg", Comment.id.empty.msg("issue comment-delete"), "issue comment-delete: give a comment id"))
    IO.print(check("id.bad.msg", Comment.id.bad.msg("pr comment-edit", "1x"), "pr comment-edit: expected a comment id, got '1x'"))
    IO.print(check("yes.msg names the comment and asks for --yes", Comment.yes.msg("issue comment-delete", "1337"), "issue comment-delete: would delete comment 1337; rerun with --yes"))
    IO.print(check("yes.msg under pr", Comment.yes.msg("pr comment-delete", "99"), "pr comment-delete: would delete comment 99; rerun with --yes"))
