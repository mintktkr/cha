# RFC 3986 encoding for one path segment or query value.
import Base
import ../lib/chaki/utf8.bend as Utf8
import ../lib/chaki/url.bend as U

def encode(s: String) -> String:
  U.pct(Utf8.encode(s))
