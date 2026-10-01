import Base
import ../src/ctx.bend as Ctx

def show(m: Maybe<&2, Ctx.Repo>) -> String:
  match m:
    case None{}:
      "none"
    case Some{Ctx.Repo{f, h, o, n}}:
      h ++ " " ++ o ++ "/" ++ n

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(show(Ctx.parse_remote("git@github.com:mintktkr/cha.git")))
    IO.print(show(Ctx.parse_remote("https://mint@tea.example.org/mint/ito.git")))
    IO.print(show(Ctx.parse_remote("ssh://git@git.example.org:2222/team/net")))
    IO.print(show(Ctx.parse_remote("https://codeberg.org/forgejo/forgejo/")))
    IO.print(Ctx.origin_url("[core]\n\tbare = false\n[remote \"up\"]\n\turl = x\n[remote \"origin\"]\n\turl = git@github.com:a/b.git\n\tfetch = +refs\n"))
    IO.print("[" ++ Ctx.token_in("https://memu:SECRET2@tea.example.org\nhttps://mint:SECRET1@tea.example.org\n", "tea.example.org", "") ++ "]")
    IO.print("[" ++ Ctx.token_in("https://mint:SECRET1@tea.example.org\nhttps://memu:SECRET2@tea.example.org\n", "tea.example.org", "memu") ++ "]")
    IO.print("[" ++ Ctx.token_in("https://mint:SECRET1@tea.example.org\n", "github.com", "") ++ "]")
