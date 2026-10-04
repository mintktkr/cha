# STUB for the port's type checks, replaced by the http lane. Not for commit.
import Base
import ./http1.bend as Http1
import ./x509.bend as X509

type Transport is Data:
  Bend{}
  Ossl{}

type Client is Data:
  Client{tls: Transport, anchors: List<&2, X509.Cert>, ms: U32}

def client(t: Transport, ms: U32) -> IO(Result<&1, &1, U32 & String, Client>):
  IO.pure(Result<&1, &1, U32 & String, Client>, Done{Client{t, Nil{}, ms}})

type Res is Data:
  Res{status: U32, headers: List<&2, Http1.Field()>, body: List<&2, U32>, url: String}

def fetch(c: Client, method: String, url: String, headers: List<&2, Http1.Field()>, body: List<&2, U32>) -> IO(Result<&1, &1, String, Res>):
  IO.pure(Result<&1, &1, String, Res>, Fail{"stub"})
