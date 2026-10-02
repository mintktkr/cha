import Base
import ../src/api.bend as Api
import ../src/cmd/runs.bend as Runs
import ../src/ui.bend as Ui
import ../src/runlogs.bend as Runlogs
import 0x584fc27920487ceab242392391418d7f/json.bend as Json
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes

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

# Decode JSON structurally: every record must be an object of string values.
def flat.values(xs: List<&1, Bytes.Bytes & Json.Val>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{(key, Json.Str{value}), rest}:
      flat.values(rest)
    case _:
      False{}

def flat.rows(xs: List<&1, Json.Val>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{Json.Obj{fields}, rest}:
      flat.values(fields) && flat.rows(rest)
    case _:
      False{}

def flat.json(m: Maybe<&1, Json.Val>) -> Bool:
  match m:
    case Some{Json.Arr{rows}}:
      flat.rows(rows)
    case _:
      False{}

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
        expect(Api.f(job, "steps.0.name"), "Compile \"app\"\nnext")
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
        jobs.last(Runs.jobs.page("", Bytes.from_string("{\"jobs\":[{\"id\":103,\"name\":\"late job\"}]}"), rows))
    case _:
      IO.die(Unit, 1, "job pages must follow the next link")

def main() -> IO(Unit):
  do IO<Unit>:
    expect(Runs.job.duration("2026-01-02T10:00:00-03:00", "2026-01-02T13:01:30Z"), "90")
    expect(Runs.job.duration("2026-01-02T13:00:00Z", "2026-01-02T13:00:00Z"), "0")
    expect(Runs.job.duration("2026-01-02T13:00:01Z", "2026-01-02T13:00:00Z"), "")
    expect(Runs.job.duration("2026-01-02T00:00:00Z", "2026-03-03T00:00:00Z"), "5184000")
    expect(Runs.job.duration("", "2026-01-02T13:00:00Z"), "")
    expect(Runs.job.duration("invalid", "2026-01-02T13:00:00Z"), "")
    expect(Runs.job.duration("2026-01-02T13:00:00Z", ""), "")
    +src : Map<&2, String> = Api.obj(Bytes.from_string(jobs.body()))
    +jobs : List<&2, Map<&2, String>> = Runs.jrows.of(src)
    jobs.next(Runs.jobs.page("page-2", Bytes.from_string(jobs.body()), Nil{}))
    expect(Nat.show(List.length(&2, Runlogs.Step, Runlogs.steps.of(Runs.job.row(src, "jobs.0"), "steps", "UPLOAD"))), "1")
    +json : String = Runs.view.json.text(fake.run(), jobs)
    yes(flat.json(Json.parse.bytes(Bytes.from_string(json))))
    check.rows(Api.rows(Bytes.from_string(json)))
    expect(Nat.show(List.length(&2, Map<&2, String>, Api.rows(Bytes.from_string(Runs.view.json.text(fake.run(), Nil{}))))), "1")
    +text : String = Runs.view.text(False{}, fake.run(), jobs)
    yes(String.contains(text, "  build  success  #101  runner-a  90s\n"))
    yes(String.contains(text, "    success  Compile \"app\"\nnext  12s\n"))
    yes(String.contains(text, "    skipped  Upload  \n"))
    expect(Bool.show(String.contains(text, "\u{1b}[")), "False")
    expect(Runs.step.text(True{}, "skipped", "Upload", "", True{}), Ui.dim(True{}, "    skipped  Upload  "))
