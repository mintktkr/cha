// The view for Tls13Client.tla: the reader's words for each phase of tls.bend's handshake.
type Vars = { [name: string]: any };

export const title = "TLS 1.3 client handshake: tls.bend at 51c3231, with an adversary server";

const PHASE: { [phase: string]: string } = {
  hello: "Waiting for the ServerHello",
  ee: "Waiting for the EncryptedExtensions",
  cert: "Waiting for the certificate",
  verify: "Waiting for the CertificateVerify",
  fin: "Waiting for the server's Finished",
  asked: "Server's flight in, checking the certificate",
  ready: "Connected",
  closed: "Closed by the server",
  failed: "Failed",
};

export const state = (v: Vars) => PHASE[v.phase];

const GROUP: { [phase: string]: string } = {
  hello: "handshake",
  ee: "handshake",
  cert: "handshake",
  verify: "handshake",
  fin: "handshake",
  asked: "checking",
  ready: "connected",
  closed: "over",
  failed: "over",
};

export const group = (v: Vars) => GROUP[v.phase];

export const colors = {
  handshake: "blue",
  checking: "yellow",
  connected: "teal",
  over: "pink",
};

const STEPS: { [action: string]: string } = {
  SrvServerHello: "the ServerHello arrives",
  SrvHelloRetryRequest: "the server asks for another key exchange",
  SrvLateHelloRetryRequest: "a second key-exchange request arrives",
  SrvDowngrade: "the server answers for TLS 1.2",
  SrvSmallOrderShare: "the key share is all zeros",
  SrvEncryptedExtensions: "the EncryptedExtensions arrive",
  SrvBadAlpn: "the server picks a protocol you didn't offer",
  SrvCertificate: "the chain arrives",
  SrvNoCertificate: "the chain is empty",
  SrvCertificateVerify: "the CertificateVerify arrives",
  SrvPkcs1CertificateVerify: "the CertificateVerify uses a pkcs1 scheme",
  SrvFinished: "the server's Finished checks out",
  SrvBadFinished: "the server's Finished is wrong",
  SrvApplicationDataEarly: "application data arrives early",
  SrvApplicationData: "data arrives",
  SrvAlert: "an alert arrives",
  SrvUnexpectedMessage: "an unexpected message arrives",
  ShellRefuses: "the chain or the signature is refused",
  ShellSendsData: "you send application data",
};

export const step = (action: string, from: Vars, to: Vars) => {
  if (action === "SrvCloseNotify")
    return from.phase === "ready"
      ? "the server is done sending"
      : "the server is done sending [before the handshake ends]";
  if (action === "ShellTrusts") {
    if (to.phase === "closed") return "the chain and the signature check out, and close_notify was waiting";
    if (to.phase === "failed")
      return "the chain and the signature check out, and a record that ends the connection was waiting";
    return to.delivered
      ? "the chain and the signature check out, and data was waiting"
      : "the chain and the signature check out";
  }
  if (action === "Done") return "nothing more can happen";
  return STEPS[action] ?? action;
};
