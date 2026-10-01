# help: cha help, cha help <command>, the banner. Full sparkle on a terminal, plain when piped.
import Base
import ./ui.bend as Ui

def usage(+on: Bool) -> String:
  Ui.glow(on, "cha 茶") ++ "  a forge CLI for Gitea, Forgejo and GitHub\n\n" ++
  "  cha issue list [--state open|closed|all] [--label L] [--all] [--json]\n" ++
  "  cha -R host/owner/repo <command> ...   use another repo than the checkout's\n"

# cha help [command]
def run(+on: Bool, args: List<&2, String>) -> IO(Unit):
  IO.write(usage(on))
