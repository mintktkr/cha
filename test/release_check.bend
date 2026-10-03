# offline checks for the release command's pure pieces: no network, no forge.
import Base
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
import ../src/ctx.bend as Ctx
import ../src/cli.bend as Cli
import ../src/api.bend as Api
import ../src/cmd/release.bend as Release

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

# a release with everything a view reads, and one with a single attachment
def full() -> String:
  "{\"tag_name\":\"v0.1.0\",\"name\":\"cha 0.1.0\",\"published_at\":\"2026-10-02T19:37:26Z\",\"html_url\":\"https://example.org/rel/v0.1.0\",\"body\":\"note\\n\",\"assets\":[{\"name\":\"cha-0.1.0-1-x86_64.pkg.tar.zst\",\"size\":1687933,\"browser_download_url\":\"https://example.org/rel/download/v0.1.0/cha.pkg.tar.zst\"}]}"

def bare() -> String:
  "{\"tag_name\":\"v0.1.0\",\"assets\":[]}"

def row(+s: String) -> Map<&2, String>:
  Release.release.row(Api.obj(Bytes.from_string(s)))

def joined(xs: List<&2, String>) -> String:
  String.join(xs, ",")

def gitea() -> Ctx.Repo:
  Ctx.Repo{Ctx.Gitea{}, "tea.example.org", "memu", "sandbox"}

def github() -> Ctx.Repo:
  Ctx.Repo{Ctx.GitHub{}, "github.com", "memu", "sandbox"}

# a release as each forge sends it: Gitea by id, GitHub also carrying its upload template

def gitea.release() -> Map<&2, String>:
  Api.obj(Bytes.from_string("{\"id\":7}"))

def github.release() -> Map<&2, String>:
  Api.obj(Bytes.from_string("{\"id\":402102889,\"upload_url\":\"https://uploads.github.com/repos/memu/sandbox/releases/402102889/assets{?name,label}\"}"))

def env() -> Cli.Env:
  Cli.Env{gitea(), "", False{}, Cli.Off{}, Nil{}}

# the one value a header map holds for k, "" when it holds none
def header.last(r: Map<&2, List<&2, String>> & List<&2, String>) -> String:
  (m, vs) = r
  Ctx.last(vs)

def header(+m: Map<&2, List<&2, String>>, +k: String) -> String:
  header.last(Map.get(List<&2, String>, Nil{}, m, k))

# the framing a multipart body must have around data, built from the head and the tail
# so the checks compare the whole request framing, not just its pieces
def framed(+name: String, +data: String) -> String:
  Release.mp.head("B", "attachment", name) ++ data ++ Release.mp.tail("B")

def framed.body(+name: String, +data: String) -> String:
  Bytes.to_string(Release.mp.body("B", "attachment", name, Bytes.from_string(data)))

# bytes no text field may lose: a NUL, a high byte and an A

def binary() -> String:
  String.from_list([Chr{0}, Chr{255}, Chr{128}, Chr{65}])

# the bytes a read gave back, from a list of bytes text cannot hold

def listed() -> String:
  Bytes.to_string(Release.read.bytes.of([0, 255, 128, 65], Bytes.new(4), 0))

# a file with known bytes, so the read path is checked without a text decode
# (File.read decodes UTF-8 on the JS lane, which is why an upload reads bytes)

def asset() -> String:
  "test/release_check_asset.txt"

def main() -> IO(Unit):
  do IO<Unit>:
    expect(Release.asset.line(False{}, row(full()), 0), "  cha-0.1.0-1-x86_64.pkg.tar.zst  1687933  https://example.org/rel/download/v0.1.0/cha.pkg.tar.zst\n")
    expect(Release.asset.line(True{}, row(full()), 0), "  cha-0.1.0-1-x86_64.pkg.tar.zst  \u{1b}[2m1687933\u{1b}[22m  https://example.org/rel/download/v0.1.0/cha.pkg.tar.zst\n")
    expect(Release.asset.block(False{}, row(full())), "assets:\n  cha-0.1.0-1-x86_64.pkg.tar.zst  1687933  https://example.org/rel/download/v0.1.0/cha.pkg.tar.zst\n")
    expect(Release.asset.block(False{}, row(bare())), "")
    expect(Release.view.text(False{}, row(full())), "v0.1.0  cha 0.1.0\n2026-10-02\nhttps://example.org/rel/v0.1.0\n\nnote\n\nassets:\n  cha-0.1.0-1-x86_64.pkg.tar.zst  1687933  https://example.org/rel/download/v0.1.0/cha.pkg.tar.zst\n")
    expect(Release.view.text(False{}, row(bare())), "v0.1.0  \n\n\n")
    expect(joined(Release.view.fields(row(full()))), "tag_name,name,published,draft,prerelease,body,html_url,assets.#,assets.0.name,assets.0.size,assets.0.browser_download_url")
    expect(joined(Release.view.fields(row(bare()))), "tag_name,name,published,draft,prerelease,body,html_url,assets.#")
    expect(Release.base.name("/tmp/cha-0.1.0-1-x86_64.pkg.tar.zst"), "cha-0.1.0-1-x86_64.pkg.tar.zst")
    expect(Release.base.name("cha.pkg"), "cha.pkg")
    expect(Release.upload.url(Ctx.Gitea{}, gitea(), gitea.release(), "a b.pkg"), "repos/memu/sandbox/releases/7/assets?name=a%20b.pkg")
    expect(Release.upload.url(Ctx.Gitea{}, gitea(), gitea.release(), "a/b.pkg"), "repos/memu/sandbox/releases/7/assets?name=a%2Fb.pkg")
    expect(Release.upload.url(Ctx.GitHub{}, github(), github.release(), "a b.pkg"), "https://uploads.github.com/repos/memu/sandbox/releases/402102889/assets?name=a%20b.pkg")
    expect(Release.upload.template("https://uploads.example.org/repos/memu/sandbox/releases/7/assets{?name,label}", "a%20b.pkg"), "https://uploads.example.org/repos/memu/sandbox/releases/7/assets?name=a%20b.pkg")
    expect(Release.upload.template("https://uploads.example.org/repos/memu/sandbox/releases/7/assets", "cha.pkg"), "https://uploads.example.org/repos/memu/sandbox/releases/7/assets?name=cha.pkg")
    expect(header(Release.upload.headers(Ctx.GitHub{}, "B"), "content-type"), "application/octet-stream")
    expect(header(Release.upload.headers(Ctx.Gitea{}, "B"), "content-type"), "multipart/form-data; boundary=B")
    expect(Bytes.to_string(Release.upload.body(Ctx.GitHub{}, "B", "cha.pkg", Bytes.from_string("hi"))), "hi")
    expect(Bytes.to_string(Release.upload.body(Ctx.Gitea{}, "B", "cha.pkg", Bytes.from_string("hi"))), framed("cha.pkg", "hi"))
    expect(Release.mp.name("a.pkg"), "a.pkg")
    expect(Release.mp.name("a\"b\\c\r\nd.pkg"), "abcd.pkg")
    expect(Release.mp.name("cha-0.1.0-1-x86_64.pkg.tar.zst"), "cha-0.1.0-1-x86_64.pkg.tar.zst")
    expect(framed.body("a.pkg", "hi"), framed("a.pkg", "hi"))
    expect(framed.body("a\"b.pkg", binary()), framed("ab.pkg", binary()))
    expect(framed.body("cha.pkg", binary()), "--B\r\nContent-Disposition: form-data; name=\"attachment\"; filename=\"cha.pkg\"\r\nContent-Type: application/octet-stream\r\n\r\n" ++ binary() ++ "\r\n--B--\r\n")
    text : String <- Release.read.file(env(), asset(), False{})
    expect(text, "cha asset fixture\n")
    data : Bytes.Bytes <- Release.read.bytes(env(), asset())
    expect(Bytes.to_string(data), "cha asset fixture\n")
    expect(listed(), binary())
