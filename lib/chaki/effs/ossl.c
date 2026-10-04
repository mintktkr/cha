// Ossl
// ====
// TLS through the system's OpenSSL 3, loaded with dlopen at run time: the binary links
// nothing extra. The socket is Base's non-blocking fd, so a handshake or a read that
// needs more of the peer parks the computation on it until the fd is ready or the
// wait's deadline passes.

#if defined(CID(available)) || defined(CID(connect)) || defined(CID(send)) \
  || defined(CID(recv)) || defined(CID(close))

#ifndef OSSL_EFFS
#define OSSL_EFFS

#include <dlfcn.h>
#include <stdio.h>

// OpenSSL's numbers, so this builds without its headers; the library is what loads.
#define OSSL_TLS1_2        0x0303  // TLS1_2_VERSION
#define OSSL_MIN_PROTO     123     // SSL_CTRL_SET_MIN_PROTO_VERSION
#define OSSL_SNI           55      // SSL_CTRL_SET_TLSEXT_HOSTNAME
#define OSSL_SNI_HOST      0       // TLSEXT_NAMETYPE_host_name
#define OSSL_PEER          1       // SSL_VERIFY_PEER
#define OSSL_OK            0       // X509_V_OK
#define OSSL_E_SSL         1
#define OSSL_E_WANT_READ   2
#define OSSL_E_WANT_WRITE  3
#define OSSL_E_SYSCALL     5
#define OSSL_E_ZERO_RETURN 6
#define OSSL_EOF_REASON    294     // SSL_R_UNEXPECTED_EOF_WHILE_READING
#define OSSL_ALPN          "\x08" "http/1.1"
#define OSSL_ALPN_LEN      9
#define OSSL_FDS           64

// Every function this file calls, resolved once. state: 0 untried, 1 loaded, -1 no.
static struct {
  int           state;
  const void*   (*TLS_client_method)(void);
  void*         (*SSL_CTX_new)(const void*);
  int           (*SSL_CTX_set_default_verify_paths)(void*);
  long          (*SSL_CTX_ctrl)(void*, int, long, void*);
  void          (*SSL_CTX_set_verify)(void*, int, void*);
  void*         (*SSL_new)(void*);
  int           (*SSL_set_fd)(void*, int);
  int           (*SSL_set1_host)(void*, const char*);
  long          (*SSL_ctrl)(void*, int, long, void*);
  int           (*SSL_set_alpn_protos)(void*, const unsigned char*, unsigned);
  int           (*SSL_connect)(void*);
  int           (*SSL_get_error)(const void*, int);
  long          (*SSL_get_verify_result)(const void*);
  const char*   (*X509_verify_cert_error_string)(long);
  unsigned long (*ERR_peek_last_error)(void);
  unsigned long (*ERR_get_error)(void);
  void          (*ERR_error_string_n)(unsigned long, char*, size_t);
  int           (*SSL_read)(void*, void*, int);
  int           (*SSL_write)(void*, const void*, int);
  int           (*SSL_shutdown)(void*);
  void          (*SSL_free)(void*);
  void          (*SSL_CTX_free)(void*);
} ossl;

// libssl 3, from CHAKI_LIBSSL else the first name that loads. Every symbol must
// resolve, or available() answers no.
static bool ossl_load(void) {
  if (ossl.state != 0) {
    return ossl.state > 0;
  }
  ossl.state = -1;
  const char* paths[] = { "libssl.so.3", "libssl.3.dylib", "/opt/homebrew/lib/libssl.3.dylib",
    "/usr/local/lib/libssl.3.dylib", "/usr/lib/libssl.so.3" };
  const char* over = getenv("CHAKI_LIBSSL");
  void* h = over != NULL ? dlopen(over, RTLD_NOW | RTLD_LOCAL) : NULL;
  for (u64 i = 0; h == NULL && i < sizeof(paths) / sizeof(paths[0]); i += 1) {
    h = dlopen(paths[i], RTLD_NOW | RTLD_LOCAL);
  }
  if (h == NULL) {
    return false;
  }
  ossl.TLS_client_method = dlsym(h, "TLS_client_method");
  ossl.SSL_CTX_new = dlsym(h, "SSL_CTX_new");
  ossl.SSL_CTX_set_default_verify_paths = dlsym(h, "SSL_CTX_set_default_verify_paths");
  ossl.SSL_CTX_ctrl = dlsym(h, "SSL_CTX_ctrl");
  ossl.SSL_CTX_set_verify = dlsym(h, "SSL_CTX_set_verify");
  ossl.SSL_new = dlsym(h, "SSL_new");
  ossl.SSL_set_fd = dlsym(h, "SSL_set_fd");
  ossl.SSL_set1_host = dlsym(h, "SSL_set1_host");
  ossl.SSL_ctrl = dlsym(h, "SSL_ctrl");
  ossl.SSL_set_alpn_protos = dlsym(h, "SSL_set_alpn_protos");
  ossl.SSL_connect = dlsym(h, "SSL_connect");
  ossl.SSL_get_error = dlsym(h, "SSL_get_error");
  ossl.SSL_get_verify_result = dlsym(h, "SSL_get_verify_result");
  ossl.X509_verify_cert_error_string = dlsym(h, "X509_verify_cert_error_string");
  ossl.ERR_peek_last_error = dlsym(h, "ERR_peek_last_error");
  ossl.ERR_get_error = dlsym(h, "ERR_get_error");
  ossl.ERR_error_string_n = dlsym(h, "ERR_error_string_n");
  ossl.SSL_read = dlsym(h, "SSL_read");
  ossl.SSL_write = dlsym(h, "SSL_write");
  ossl.SSL_shutdown = dlsym(h, "SSL_shutdown");
  ossl.SSL_free = dlsym(h, "SSL_free");
  ossl.SSL_CTX_free = dlsym(h, "SSL_CTX_free");
  bool ok = ossl.TLS_client_method && ossl.SSL_CTX_new && ossl.SSL_CTX_set_default_verify_paths
    && ossl.SSL_CTX_ctrl && ossl.SSL_CTX_set_verify && ossl.SSL_new && ossl.SSL_set_fd
    && ossl.SSL_set1_host && ossl.SSL_ctrl && ossl.SSL_set_alpn_protos && ossl.SSL_connect
    && ossl.SSL_get_error && ossl.SSL_get_verify_result && ossl.X509_verify_cert_error_string
    && ossl.ERR_peek_last_error && ossl.ERR_get_error && ossl.ERR_error_string_n
    && ossl.SSL_read && ossl.SSL_write && ossl.SSL_shutdown && ossl.SSL_free
    && ossl.SSL_CTX_free;
  ossl.state = ok ? 1 : -1;
  return ok;
}

// One session per connected socket. fds are small, so this is an array that doubles as
// sockets come.
static void** ossl_socks;
static u32    ossl_room;

static void* ossl_get(int fd) {
  return fd >= 0 && (u32)fd < ossl_room ? ossl_socks[fd] : NULL;
}

static void* ossl_take(int fd) {
  void* s = ossl_get(fd);
  if (s != NULL) {
    ossl_socks[fd] = NULL;
  }
  return s;
}

static void ossl_put(int fd, void* s) {
  if ((u32)fd >= ossl_room) {
    u32 n = ossl_room == 0 ? OSSL_FDS : ossl_room;
    while (n <= (u32)fd) {
      n *= 2;
    }
    ossl_socks = io_mem(realloc(ossl_socks, n * sizeof(void*)));
    memset(ossl_socks + ossl_room, 0, (n - ossl_room) * sizeof(void*));
    ossl_room = n;
  }
  ossl_socks[fd] = s;
}

// One client context for every session: the system's trust store, a peer certificate
// that must verify, and TLS 1.2 as the floor. A half-built context is dropped, so the
// next call tries again.
static void* ossl_ctx;

static bool ossl_ctx_open(const char** why) {
  if (ossl_ctx != NULL) {
    return true;
  }
  ossl_ctx = ossl.SSL_CTX_new(ossl.TLS_client_method());
  if (ossl_ctx == NULL) {
    *why = "SSL_CTX_new failed";
    return false;
  }
  ossl.SSL_CTX_set_verify(ossl_ctx, OSSL_PEER, NULL);
  if (!ossl.SSL_CTX_set_default_verify_paths(ossl_ctx)) {
    *why = "the system's trusted certificates did not load";
  } else if (ossl.SSL_CTX_ctrl(ossl_ctx, OSSL_MIN_PROTO, OSSL_TLS1_2, NULL) <= 0) {
    *why = "this OpenSSL cannot refuse TLS below 1.2";
  } else {
    return true;
  }
  ossl.SSL_CTX_free(ossl_ctx);
  ossl_ctx = NULL;
  return false;
}

// Why the peer's certificate did not verify (expired, wrong host, unknown issuer), or
// NULL when it did.
static const char* ossl_verify_why(void* s) {
  long v = s == NULL ? OSSL_OK : ossl.SSL_get_verify_result(s);
  return v == OSSL_OK ? NULL : ossl.X509_verify_cert_error_string(v);
}

// The error queue's oldest entry, as text, and the queue emptied. OpenSSL's own words:
// never key material.
static const char* ossl_ssl_text(void) {
  static char text[256];
  unsigned long er = ossl.ERR_get_error();
  if (er == 0) {
    return NULL;
  }
  text[0] = '\0';
  ossl.ERR_error_string_n(er, text, sizeof text);
  while (ossl.ERR_get_error() != 0) {
  }
  return text;
}

// The text for a failed TLS call: the chain's reason when it did not verify, else the
// error queue's, else the socket's errno for a syscall one. NULL means strerror(code).
static const char* ossl_why(void* s, int err) {
  static char text[256];
  const char* why = ossl_verify_why(s);
  if (why != NULL) {
    snprintf(text, sizeof text, "certificate verify failed: %s", why);
    return text;
  }
  if (err == OSSL_E_SYSCALL) {
    return strerror(errno != 0 ? errno : ECONNRESET);
  }
  return ossl_ssl_text();
}

// The errno an effect reports: the deadline when the wait ran out, the socket's errno
// for a syscall error, EPROTO for anything else a TLS call can answer.
static u32 ossl_code(int err, bool ran_out) {
  if (ran_out) {
    return ETIMEDOUT;
  }
  if (err == OSSL_E_SYSCALL) {
    return errno != 0 ? (u32)errno : ECONNRESET;
  }
  if (err == OSSL_E_ZERO_RETURN) {
    return ECONNRESET;
  }
  return EPROTO;
}

// The poll event OpenSSL's error asks to wait for; 0 when the call is over.
static int ossl_event(int err) {
  return err == OSSL_E_WANT_READ ? POLLIN : err == OSSL_E_WANT_WRITE ? POLLOUT : 0;
}

// OpenSSL 3 answers a peer that closed without close_notify with a TLS error whose last
// entry says unexpected EOF. TLS cannot tell that from a truncated stream; a client that
// has read what it asked for has to accept it as the end.
static bool ossl_eof(void* s) {
  if (s == NULL) {
    return false;
  }
  unsigned long er = ossl.ERR_peek_last_error();
  return er != 0 && (int)(er & 0x7fffff) == OSSL_EOF_REASON;
}

#endif
#endif

#ifdef CID(available)

// Whether libssl 3 loads.
Term ossl_available_run(Env e, Term* f, IoWork* w) {
  return term_pak(ossl_load() ? CID(True) : CID(False), 0);
}

static void __attribute__((constructor)) ossl_available_use(void) {
  io_eff(CID(available), ossl_available_run, 0);
}

#endif

#ifdef CID(connect)

// The answer: the socket, then Done{Unit} or the failure. The session goes away either
// way: a failed handshake leaves nothing to close, and close(sock) frees the fd.
static Term ossl_connect_end(Env e, IoWork* w, u32 code, const char* why) {
  void* s = ossl_take((int)w->hand);
  if (s != NULL) {
    ossl.SSL_free(s);
  }
  free(w->data);
  Term r = code == 0 ? io_done(e, term_pak(CID(Unit), 0)) : io_fail(e, code, why);
  return io_tup(e, io_hand(w->hand), r);
}

// A finished handshake: the chain and the name verified (SSL_set1_host checked it), and
// nothing below TLS 1.2 was offered.
static Term ossl_connect_ok(Env e, IoWork* w, void* s) {
  return ossl_verify_why(s) == NULL ? ossl_connect_end(e, w, 0, NULL)
    : ossl_connect_end(e, w, EPROTO, ossl_why(s, 0));
}

// One handshake step; while OpenSSL wants the socket, park on it, and past the deadline
// that is ETIMEDOUT. w->word is the absolute deadline, in io_tick's microseconds.
static Term ossl_connect_step(Env e, IoWork* w) {
  void* s = ossl_get((int)w->hand);
  int rc = s == NULL ? -1 : ossl.SSL_connect(s);
  if (rc == 1) {
    return ossl_connect_ok(e, w, s);
  }
  int err = s == NULL ? OSSL_E_SSL : ossl.SSL_get_error(s, rc);
  int what = ossl_event(err);
  if (what != 0 && io_tick() < (u64)w->word) {
    return io_wait_on(w, (int)w->hand, what, (u64)w->word, ossl_connect_step);
  }
  return ossl_connect_end(e, w, ossl_code(err, what != 0), ossl_why(s, err));
}

// connect(sock, host, ms)
Term ossl_connect_run(Env e, Term* f, IoWork* w) {
  int fd = (int)io_hand_v(f[0]);
  w->hand = (intptr_t)fd;
  w->word = (intptr_t)(io_tick() + (u64)(u32)f[2] * 1000ull);
  w->data = io_cstr(e, f[1], &w->size);
  if (ossl_get(fd) != NULL) {
    return ossl_connect_end(e, w, EALREADY, "this socket already has a TLS session");
  }
  if (!ossl_load()) {
    return ossl_connect_end(e, w, ENOENT, "libssl 3 did not load; set CHAKI_LIBSSL to its path");
  }
  const char* why = NULL;
  if (!ossl_ctx_open(&why)) {
    return ossl_connect_end(e, w, ENOENT, why);
  }
  void* s = ossl.SSL_new(ossl_ctx);
  if (s == NULL) {
    return ossl_connect_end(e, w, ENOMEM, "SSL_new failed");
  }
  ossl_put(fd, s);
  bool set = ossl.SSL_set_fd(s, fd) == 1
    && ossl.SSL_set1_host(s, w->data) == 1
    && ossl.SSL_ctrl(s, OSSL_SNI, OSSL_SNI_HOST, w->data) == 1
    && ossl.SSL_set_alpn_protos(s, (const unsigned char*)OSSL_ALPN, OSSL_ALPN_LEN) == 0;
  if (!set) {
    return ossl_connect_end(e, w, EPROTO, ossl_ssl_text());
  }
  return ossl_connect_step(e, w);
}

static void __attribute__((constructor)) ossl_connect_use(void) {
  io_eff(CID(connect), ossl_connect_run, 0);
}

#endif

#ifdef CID(send)

// The answer: the socket, then Done{Unit} or the failure.
static Term ossl_send_end(Env e, IoWork* w, u32 code, const char* why) {
  free(w->data);
  Term r = code == 0 ? io_done(e, term_pak(CID(Unit), 0)) : io_fail(e, code, why);
  return io_tup(e, io_hand(w->hand), r);
}

// What is left of the buffer; a full socket (non-blocking, so EAGAIN) parks until it is
// writable again. A send has no deadline: the peer either takes it or the socket breaks.
static Term ossl_send_more(Env e, IoWork* w) {
  void* s = ossl_get((int)w->hand);
  while (s != NULL && (u64)w->made < (u64)w->size) {
    int n = ossl.SSL_write(s, w->data + w->made, (int)((u64)w->size - (u64)w->made));
    if (n > 0) {
      w->made += n;
      continue;
    }
    int err = ossl.SSL_get_error(s, n);
    int what = ossl_event(err);
    if (what == 0) {
      return ossl_send_end(e, w, ossl_code(err, false), ossl_why(s, err));
    }
    return io_wait_on(w, (int)w->hand, what, 0, ossl_send_more);
  }
  return s == NULL
    ? ossl_send_end(e, w, EBADF, "this socket has no TLS session")
    : ossl_send_end(e, w, 0, NULL);
}

// send(sock, data)
Term ossl_send_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  w->data = io_cbuf(e, f[1], &w->size, CID(Con));
  w->made = 0;
  // A byte past 255 fails with EINVAL before anything is sent.
  return w->data == NULL ? ossl_send_end(e, w, EINVAL, NULL) : ossl_send_more(e, w);
}

static void __attribute__((constructor)) ossl_send_use(void) {
  io_eff(CID(send), ossl_send_run, 0);
}

#endif

#ifdef CID(recv)

static Term ossl_recv_end(Env e, IoWork* w) {
  Term r = io_done(e, io_list(e, w->data, (u64)w->size));
  free(w->data);
  return io_tup(e, io_hand(w->hand), r);
}

static Term ossl_recv_fail(Env e, IoWork* w, u32 code, const char* why) {
  free(w->data);
  return io_tup(e, io_hand(w->hand), io_fail(e, code, why));
}

// One read; while OpenSSL wants the socket, park on it, and past the deadline that is
// ETIMEDOUT. w->word is the absolute deadline (0 for none), w->made the bytes asked for.
// Done{[]} is the peer's close: a close_notify, or the plain EOF of a peer that closed
// without one.
static Term ossl_recv_more(Env e, IoWork* w) {
  void* s = ossl_get((int)w->hand);
  if (s == NULL) {
    return ossl_recv_fail(e, w, EBADF, "this socket has no TLS session");
  }
  int n = ossl.SSL_read(s, w->data, (int)w->made);
  if (n > 0) {
    w->size = (intptr_t)n;
    return ossl_recv_end(e, w);
  }
  int err = ossl.SSL_get_error(s, n);
  if (err == OSSL_E_ZERO_RETURN || (err == OSSL_E_SYSCALL && n == 0 && errno == 0) || ossl_eof(s)) {
    w->size = 0;
    return ossl_recv_end(e, w);
  }
  int what = ossl_event(err);
  if (what != 0 && ((u64)w->word == 0 || io_tick() < (u64)w->word)) {
    return io_wait_on(w, (int)w->hand, what, (u64)w->word, ossl_recv_more);
  }
  return ossl_recv_fail(e, w, ossl_code(err, what != 0), ossl_why(s, err));
}

// recv(sock, max, ms)
Term ossl_recv_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  w->data = NULL;
  w->made = f[1] < INT32_MAX ? (intptr_t)f[1] : INT32_MAX;
  w->word = (intptr_t)(io_tick() + (u64)(u32)f[2] * 1000ull);
  if (f[1] == 0) {
    return ossl_recv_fail(e, w, EINVAL, NULL);
  }
  w->data = io_mem(malloc((size_t)w->made));
  return ossl_recv_more(e, w);
}

static void __attribute__((constructor)) ossl_recv_use(void) {
  io_eff(CID(recv), ossl_recv_run, 0);
}

#endif

#ifdef CID(close)

// close(sock): close_notify, the session, the socket. The peer's answering close_notify
// is not waited for, so what a full socket cannot flush is dropped.
Term ossl_close_run(Env e, Term* f, IoWork* w) {
  int fd = (int)io_hand_v(f[0]);
  void* s = ossl_take(fd);
  if (s != NULL) {
    ossl.SSL_shutdown(s);
    ossl.SSL_free(s);
  }
  close(fd);
  return term_pak(CID(Unit), 0);
}

static void __attribute__((constructor)) ossl_close_use(void) {
  io_eff(CID(close), ossl_close_run, 0);
}

#endif
