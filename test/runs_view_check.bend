import Base
import ../src/api.bend as Api
import ../src/cmd/runs.bend as Runs
import ../src/ui.bend as Ui
import ../src/runlogs.bend as Runlogs
import ../lib/chaki/utf8.bend as Utf8

def expect.if(+got: String, +want: String, same: Bool) -> IO(Unit):
  match same:
    case True{}:
      IO.print("ok  " ++ got)
    case False{}:
      do IO<Unit>:
        IO.print("bad " ++ got ++ " != " ++ want)
        IO.die(Unit, 1, "")

def expect(+got: String, +want: String) -> IO(Unit):
  expect.if(got, want, String.eq(got, want))

def yes(got: Bool) -> IO(Unit):
  expect(Bool.show(got), "True")

# A deliberately synthetic response, including escaped text and missing metadata.
def jobs.body() -> String:
  "{\"jobs\":[{\"id\":101,\"name\":\"build\",\"status\":\"completed\",\"conclusion\":\"success\",\"runner_name\":\"runner-a\",\"started_at\":\"2026-01-02T10:00:00-03:00\",\"completed_at\":\"2026-01-02T13:01:30Z\",\"steps\":[{\"number\":1,\"name\":\"Compile \\\"app\\\"\\nnext\",\"status\":\"completed\",\"conclusion\":\"success\",\"started_at\":\"2026-01-02T13:00:00Z\",\"completed_at\":\"2026-01-02T13:00:12Z\"},{\"number\":2,\"name\":\"Upload\",\"status\":\"completed\",\"conclusion\":\"skipped\",\"started_at\":null,\"completed_at\":null}]},{\"id\":102,\"name\":\"pending\",\"status\":\"queued\",\"steps\":[]}]}"

def fake.run() -> Map<&2, String>:
  m = Map.new(&2, String)
  m = Map.set(&2, String, m, "kind", "run")
  Map.set(&2, String, m, "id", "7")

# View JSON must stay a flat array of string-valued objects: it parses back to one
# row per record through Api.rows, and check.rows below reads every field of each.
def flat.count(+json: String, +want: String) -> IO(Unit):
  expect(Nat.show(List.length(&2, Map<&2, String>, Api.rows(Utf8.encode(json)))), want)

def check.rows(xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match xs:
    case Con{+run, Con{+job, Con{+pending, Nil{}}}}:
      do IO<Unit>:
        expect(Api.f(run, "id"), "7")
        expect(Api.f(run, "kind"), "run")
        expect(Api.f(job, "kind"), "job")
        expect(Api.f(job, "id"), "101")
        expect(Api.f(job, "runner_name"), "runner-a")
        expect(Api.f(job, "started_at"), "2026-01-02T10:00:00-03:00")
        expect(Api.f(job, "completed_at"), "2026-01-02T13:01:30Z")
        expect(Api.f(job, "duration"), "90")
        expect(Api.f(job, "steps.#"), "2")
        expect(Api.raw.f(job, "steps.0.name"), "Compile \"app\"\nnext")
        expect(Api.f(job, "steps.0.duration"), "12")
        expect(Api.f(job, "steps.1.state"), "skipped")
        expect(Api.f(job, "steps.1.duration"), "")
        expect(Api.f(pending, "id"), "102")
        expect(Api.f(pending, "runner_name"), "")
        expect(Api.f(pending, "duration"), "")
        expect(Api.f(pending, "steps.#"), "0")
    case _:
      IO.die(Unit, 1, "view JSON must contain one run followed by two jobs")

def jobs.last(page: Runs.JobPages) -> IO(Unit):
  match page:
    case Runs.NextJobs{True{}, next, +rows}:
      do IO<Unit>:
        expect(Nat.show(List.length(&2, Map<&2, String>, rows)), "3")
        expect(Nat.show(List.length(&2, Map<&2, String>, Runs.keep.rows(rows, "LATE JOB", False{}))), "1")
    case _:
      IO.die(Unit, 1, "last job page must retain prior rows")

def jobs.next(page: Runs.JobPages) -> IO(Unit):
  match page:
    case Runs.NextJobs{False{}, +next, +rows}:
      do IO<Unit>:
        expect(next, "page-2")
        jobs.last(Runs.jobs.page("", "", Utf8.encode("{\"jobs\":[{\"id\":103,\"name\":\"late job\"}]}"), rows))
    case _:
      IO.die(Unit, 1, "job pages must follow the next link")

def gitea.jobs(page: Runs.JobPages) -> IO(Unit):
  match page:
    case Runs.NextJobs{False{}, +next, rows}:
      expect(next, "fallback-2")
    case _:
      IO.die(Unit, 1, "Gitea job pages short of total_count must continue")

def gitea.jobs.done(page: Runs.JobPages) -> IO(Unit):
  match page:
    case Runs.NextJobs{True{}, next, rows}:
      expect("stopped", "stopped")
    case _:
      IO.die(Unit, 1, "Gitea job pages must stop at total_count or an empty page")

# Forgejo answers the job list with a bare array, and each job carries a task_id.
def fj.jobs.body() -> String:
  "[{\"id\":13655010,\"run_id\":7448154,\"attempt\":1,\"handle\":\"38df3c67-e365-43e0-b90c-cd4fbef034c1\",\"repo_id\":73144,\"owner_id\":70422,\"name\":\"merge-conditions\",\"needs\":null,\"runs_on\":[\"docker\"],\"task_id\":10078131,\"status\":\"success\"},{\"id\":13655011,\"run_id\":7448154,\"name\":\"build\",\"runs_on\":[\"docker\"],\"task_id\":10078132,\"status\":\"running\"}]"

def fj.check.jobs(xs: List<&2, Map<&2, String>>) -> IO(Unit):
  match xs:
    case Con{+job, Con{+active, Nil{}}}:
      do IO<Unit>:
        expect(Api.f(job, "kind"), "job")
        expect(Api.f(job, "id"), "13655010")
        expect(Api.f(job, "name"), "merge-conditions")
        expect(Api.f(job, "status"), "completed")
        expect(Api.f(job, "conclusion"), "success")
        expect(Api.f(job, "state"), "success")
        expect(Api.f(job, "runner_name"), "")
        expect(Api.f(job, "duration"), "")
        expect(Api.f(job, "steps.#"), "0")
        expect(Api.f(active, "state"), "running")
        expect(Api.f(active, "conclusion"), "")
    case _:
      IO.die(Unit, 1, "a bare job array must flatten to one row per job")

def fj.check.page(page: Runs.JobPages) -> IO(Unit):
  match page:
    case Runs.NextJobs{True{}, next, +rows}:
      do IO<Unit>:
        expect(next, "")
        expect(Nat.show(List.length(&2, Map<&2, String>, rows)), "2")
    case _:
      IO.die(Unit, 1, "a bare job array is the whole list, with no link to follow")

def main() -> IO(Unit):
  do IO<Unit>:
    expect(Runs.job.duration("2026-01-02T10:00:00-03:00", "2026-01-02T13:01:30Z"), "90")
    expect(Runs.job.duration("2026-01-02T13:00:00Z", "2026-01-02T13:00:00Z"), "0")
    expect(Runs.job.duration("2026-01-02T13:00:01Z", "2026-01-02T13:00:00Z"), "")
    expect(Runs.job.duration("2026-01-02T00:00:00Z", "2026-03-03T00:00:00Z"), "5184000")
    expect(Runs.job.duration("", "2026-01-02T13:00:00Z"), "")
    expect(Runs.job.duration("invalid", "2026-01-02T13:00:00Z"), "")
    expect(Runs.job.duration("2026-01-02T13:00:00Z", ""), "")
    +src : Map<&2, String> = Api.obj(Utf8.encode(jobs.body()))
    +jobs : List<&2, Map<&2, String>> = Runs.jrows.of(src)
    jobs.next(Runs.jobs.page("page-2", "", Utf8.encode(jobs.body()), Nil{}))
    gitea.jobs(Runs.jobs.page("", "fallback-2", Utf8.encode("{\"total_count\":3,\"jobs\":[{\"id\":1},{\"id\":2}]}"), Nil{}))
    gitea.jobs.done(Runs.jobs.page("", "fallback-2", Utf8.encode("{\"total_count\":2,\"jobs\":[{\"id\":1},{\"id\":2}]}"), Nil{}))
    gitea.jobs.done(Runs.jobs.page("", "fallback-2", Utf8.encode("{\"total_count\":9,\"jobs\":[]}"), Nil{}))
    expect(Nat.show(List.length(&2, Runlogs.Step, Runlogs.steps.of(Runs.job.row(src, "jobs.0"), "steps", "UPLOAD"))), "1")
    +json : String = Runs.view.json.text(fake.run(), jobs)
    flat.count(json, "3")
    check.rows(Api.rows(Utf8.encode(json)))
    expect(Nat.show(List.length(&2, Map<&2, String>, Api.rows(Utf8.encode(Runs.view.json.text(fake.run(), Nil{}))))), "1")
    +text : String = Runs.view.text(False{}, fake.run(), jobs)
    yes(String.contains(text, "  build  success  #101  runner-a  90s\n"))
    yes(String.contains(text, "    success  Compile \"app\" next  12s\n"))
    yes(String.contains(text, "    skipped  Upload  \n"))
    expect(Bool.show(String.contains(text, "\u{1b}[")), "False")
    expect(Runs.step.text(True{}, "skipped", "Upload", "", True{}), Ui.dim(True{}, "    skipped  Upload  "))
    fj.check.jobs(Runs.jrows.of(Api.obj(Utf8.encode(fj.jobs.body()))))
    fj.check.page(Runs.jobs.page("", "fallback-2", Utf8.encode(fj.jobs.body()), Nil{}))
