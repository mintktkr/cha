// The view for Redirect.tla: where the chain is, in the reader's words.
type Vars = { [name: string]: any };

// Redirect.cfg's MaxHops
const MAX_HOPS = 4;

export const title = "Redirects: two origins, an https start, a hop budget of 4 (http.bend and hop.bend at cf7905c)";

const scheme = (v: Vars) => (v.secure ? "https" : "http");
const how = (v: Vars) => (v.creds ? "with your credentials" : "without your credentials");

export const state = (v: Vars) => {
  if (v.pc === "stopped") return "Chain stopped";
  if (v.pc === "done") return `Answer from ${v.at} over ${scheme(v)}, ${how(v)}`;
  return `Hop ${v.hop} of ${MAX_HOPS}: ${v.at} over ${scheme(v)}, ${how(v)}`;
};

export const group = (v: Vars) => {
  if (v.pc === "stopped") return "stopped";
  if (v.pc === "done") return "answered";
  return "asking";
};

export const colors = {
  asking: "blue",
  answered: "teal",
  stopped: "pink",
};

const STEPS: { [action: string]: string } = {
  Answer: "the server answers with no redirect",
  RedirectHere: "the server redirects to the same origin",
  RedirectElsewhere: "the server redirects to the other origin",
  RedirectToHttp: "the server redirects to http [refused]",
  TooManyRedirects: "the server redirects again [no hops left]",
};

export const step = (action: string) => STEPS[action] ?? "nothing more can happen";
