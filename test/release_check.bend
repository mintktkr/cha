# offline checks for the release command's pure pieces: no network, no forge.
import Base
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes
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
