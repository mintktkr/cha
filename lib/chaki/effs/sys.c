// sys, C side: the calls the JS side mirrors. The dial blocks (getaddrinfo, then a
// non-blocking connect per address), so it runs on a helper thread with io_work; recv
// parks on the fd with an absolute deadline. Every fd handed back is non-blocking, as
// Base's own effects leave theirs, so Base's TCP effects work on it too.
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#ifdef CID(dial)

// what is left of the dial in ms, 0 once the deadline passed. Each address of the plan
// gets left / addresses-left of it, so no one address can eat another family's turn.
static int chaki_sys_left(IoWork* w) {
  u64 now = io_tick();
  if (now >= w->time) {
    return 0;
  }
  u64 ms = (w->time - now) / 1000000ull + 1ull;
  return ms > (u64)INT32_MAX ? INT32_MAX : (int)ms;
}

// one connect attempt: 0 when it connected, else the errno to remember. share is this
// address's own slice of the dial; the whole dial is still bounded by w->time.
static u32 chaki_sys_connect(int fd, const struct addrinfo* ai, int share) {
  if (connect(fd, ai->ai_addr, ai->ai_addrlen) == 0) {
    return 0;
  }
  if (errno != EINPROGRESS && errno != EINTR) {
    return (u32)errno;
  }
  if (share <= 0) {
    return ETIMEDOUT;
  }
  struct pollfd p = { fd, POLLOUT, 0 };
  int n;
  do {
    n = poll(&p, 1, share);
  } while (n < 0 && errno == EINTR);
  if (n == 0) {
    return ETIMEDOUT;
  }
  if (n < 0) {
    return (u32)errno;
  }
  int err = 0;
  socklen_t len = sizeof(err);
  if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len) < 0) {
    return (u32)errno;
  }
  return err == 0 ? 0 : (u32)err;
}

// the order to try: getaddrinfo's answer with its families alternating, so a black-holed
// v6 address costs at most its share before the v4 one gets its turn (RFC 8305 4). Each
// family keeps the order getaddrinfo gave it, the first address's family leads, and a third
// family counts as the other. NULL when there is nothing to try or the plan won't allocate.
static struct addrinfo** chaki_sys_plan(struct addrinfo* res, u32* n) {
  u32 len = 0;
  for (struct addrinfo* ai = res; ai != NULL; ai = ai->ai_next) {
    len += 1;
  }
  *n = len;
  struct addrinfo** order = len == 0 ? NULL : malloc((size_t)len * sizeof(*order));
  struct addrinfo** plan = len == 0 ? NULL : malloc((size_t)len * sizeof(*plan));
  if (order == NULL || plan == NULL) {
    free(order);
    free(plan);
    return NULL;
  }
  u32 same = 0;
  for (struct addrinfo* ai = res; ai != NULL; ai = ai->ai_next) {
    if (ai->ai_family == res->ai_family) {
      order[same++] = ai;
    }
  }
  u32 other = 0;
  for (struct addrinfo* ai = res; ai != NULL; ai = ai->ai_next) {
    if (ai->ai_family != res->ai_family) {
      order[same + other++] = ai;
    }
  }
  u32 a = 0;
  u32 b = 0;
  for (u32 k = 0; k < len; k += 1) {
    plan[k] = (k % 2 == 0 ? a < same : b >= other) ? order[a++] : order[same + b++];
  }
  free(order);
  return plan;
}

// on the helper thread: resolve, then try every address until one connects, each with a
// fair share of what is left of the dial. A resolve failure carries its own message,
// `<host>: <gai_strerror text>`.
static void chaki_sys_dial_call(IoWork* w) {
  struct addrinfo hints;
  struct addrinfo* res = NULL;
  char port[8];
  memset(&hints, 0, sizeof(hints));
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  snprintf(port, sizeof(port), "%u", (u32)w->made);
  int rc = getaddrinfo(w->data, port, &hints, &res);
  if (rc != 0) {
    const char* why = gai_strerror(rc);
    size_t n = strlen(w->data) + strlen(why) + 3;
    w->text = malloc(n);
    if (w->text != NULL) {
      snprintf(w->text, n, "%s: %s", w->data, why);
    }
    w->code = (u32)rc;
    return;
  }
  u32 len = 0;
  struct addrinfo** plan = chaki_sys_plan(res, &len);
  if (plan == NULL) {
    freeaddrinfo(res);
    w->made = -1;
    w->code = len == 0 ? EADDRNOTAVAIL : ENOMEM;
    return;
  }
  u32 last = 0;
  for (u32 i = 0; i < len; i += 1) {
    struct addrinfo* ai = plan[i];
    int share = chaki_sys_left(w) / (int)(len - i);
    int fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
    if (fd < 0) {
      last = (u32)errno;
      continue;
    }
    if (fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) < 0) {
      last = (u32)errno;
      close(fd);
      continue;
    }
    u32 err = chaki_sys_connect(fd, ai, share);
    if (err == 0) {
      w->made = fd;
      w->code = 0;
      free(plan);
      freeaddrinfo(res);
      return;
    }
    last = err;
    close(fd);
  }
  free(plan);
  freeaddrinfo(res);
  w->made = -1;
  w->code = last != 0 ? last : ETIMEDOUT;
}

static Term chaki_sys_dial_pack(Env e, IoWork* w) {
  Term r = w->code == 0 ? io_done(e, io_hand(w->made))
    : io_fail(e, w->code, w->text);
  free(w->data);
  free(w->text);
  return r;
}

Term chaki_sys_dial_run(Env e, Term* f, IoWork* w) {
  w->data = io_cstr(e, f[0], &w->size);
  w->made = (intptr_t)f[1];
  w->time = io_tick() + (u64)f[2] * 1000000ull;
  w->text = NULL;
  w->code = 0;
  if (f[1] > 65535 || io_nul(w->data, w->size)) {
    free(w->data);
    w->data = NULL;
    return io_fail(e, EINVAL, NULL);
  }
  return io_work(w, chaki_sys_dial_call, chaki_sys_dial_pack);
}

static void __attribute__((constructor)) chaki_sys_dial_use(void) {
  io_eff(CID(dial), chaki_sys_dial_run, 0);
}

#endif

#ifdef CID(recv)

// recv parks until the fd is readable or the deadline passes; a wake that finds nothing
// left parks again, and one past the deadline answers ETIMEDOUT. 0 bytes is Done{[]},
// the peer's close.
static Term chaki_sys_recv_more(Env e, IoWork* w) {
  int fd = (int)w->hand;
  w->size = io_sys_end(w, recv(fd, w->data, (size_t)w->made, 0));
  if ((w->code == EAGAIN || w->code == EINTR) && io_tick() < w->time) {
    return io_wait_on(w, fd, POLLIN, w->time, chaki_sys_recv_more);
  }
  if (w->code == EAGAIN || w->code == EINTR) {
    w->code = ETIMEDOUT;
  }
  Term r = w->code == 0 ? io_done(e, io_list(e, w->data, w->size))
    : io_fail(e, w->code, NULL);
  free(w->data);
  w->data = NULL;
  return io_tup(e, io_hand(w->hand), r);
}

Term chaki_sys_recv_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  if (f[1] == 0) {
    return io_tup(e, io_hand(w->hand), io_fail(e, EINVAL, NULL));
  }
  w->made = f[1] < INT32_MAX ? (intptr_t)f[1] : INT32_MAX;
  w->data = io_mem(malloc((size_t)w->made));
  w->time = io_tick() + (u64)f[2] * 1000000ull;
  return chaki_sys_recv_more(e, w);
}

static void __attribute__((constructor)) chaki_sys_recv_use(void) {
  io_eff(CID(recv), chaki_sys_recv_run, 0);
}

#endif

#ifdef CID(now)

// the wall clock, in seconds; io_tick is monotonic, so it can't answer this
Term chaki_sys_now_run(Env e, Term* f, IoWork* w) {
  return (Term)(u32)time(NULL);
}

static void __attribute__((constructor)) chaki_sys_now_use(void) {
  io_eff(CID(now), chaki_sys_now_run, 0);
}

#endif

#ifdef CID(isatty.raw)

Term chaki_sys_isatty_run(Env e, Term* f, IoWork* w) {
  return (Term)(u32)(isatty((int)f[0]) != 0);
}

static void __attribute__((constructor)) chaki_sys_isatty_use(void) {
  io_eff(CID(isatty.raw), chaki_sys_isatty_run, 0);
}

#endif

#ifdef CID(cols)

Term chaki_sys_cols_run(Env e, Term* f, IoWork* w) {
  struct winsize ws;
  return (Term)(u32)(ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 ? ws.ws_col : 0);
}

static void __attribute__((constructor)) chaki_sys_cols_use(void) {
  io_eff(CID(cols), chaki_sys_cols_run, 0);
}

#endif
