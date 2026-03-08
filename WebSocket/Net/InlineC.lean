/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import Alloy.C
open scoped Alloy.C

alloy c section

#include <lean/lean.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <sys/random.h>
#include <string.h>
#include <errno.h>
#include <stdlib.h>
#include <time.h>
#include <stdio.h>

static int set_nonblocking(int fd) {
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags < 0) return -1;
  if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) return -1;
  return 0;
}

static lean_object *mk_io_error_from_errno(int err)
{
  lean_object *msg = lean_mk_string(err == 0 ? "socket error" : strerror(err));
  return lean_io_result_mk_error(msg);
}

lean_obj_res ws_listen(uint32_t port)
{
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  if (fd < 0)
    return mk_io_error_from_errno(errno);
  int opt = 1;
  setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
  struct sockaddr_in addr;
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = htonl(INADDR_ANY);
  addr.sin_port = htons((uint16_t)port);
  if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0)
  {
    int e = errno;
    close(fd);
    return mk_io_error_from_errno(e);
  }
  if (listen(fd, 128) < 0)
  {
    int e = errno;
    close(fd);
    return mk_io_error_from_errno(e);
  }
  set_nonblocking(fd);
  return lean_io_result_mk_ok(lean_box(fd));
}

lean_obj_res ws_accept(uint32_t listen_fd)
{
  int cfd = accept((int)listen_fd, NULL, NULL);
  if (cfd < 0)
    return mk_io_error_from_errno(errno);
  int keepalive = 1;
  setsockopt(cfd, SOL_SOCKET, SO_KEEPALIVE, &keepalive, sizeof(keepalive));
  set_nonblocking(cfd);
  return lean_io_result_mk_ok(lean_box(cfd));
}

lean_obj_res ws_peer_addr(uint32_t fd)
{
  struct sockaddr_storage addr;
  socklen_t addr_len = sizeof(addr);
  char host[INET6_ADDRSTRLEN];
  memset(&addr, 0, sizeof(addr));
  memset(host, 0, sizeof(host));

  if (getpeername((int)fd, (struct sockaddr *)&addr, &addr_len) < 0)
    return mk_io_error_from_errno(errno);

  if (addr.ss_family == AF_INET) {
    struct sockaddr_in *addr4 = (struct sockaddr_in *)&addr;
    if (!inet_ntop(AF_INET, &addr4->sin_addr, host, sizeof(host)))
      return mk_io_error_from_errno(errno);
  } else if (addr.ss_family == AF_INET6) {
    struct sockaddr_in6 *addr6 = (struct sockaddr_in6 *)&addr;
    if (!inet_ntop(AF_INET6, &addr6->sin6_addr, host, sizeof(host)))
      return mk_io_error_from_errno(errno);
  } else {
    return lean_io_result_mk_error(lean_mk_string("unsupported address family"));
  }

  return lean_io_result_mk_ok(lean_mk_string(host));
}

lean_obj_res ws_close(uint32_t fd)
{
  if (close((int)fd) < 0)
    return mk_io_error_from_errno(errno);
  return lean_io_result_mk_ok(lean_box(0));
}

lean_obj_res ws_recv_bytes(uint32_t fd, size_t max)
{
  if (max == 0)
    max = 1;
  if (max > 65536)
    max = 65536;
  lean_object *ba = lean_alloc_sarray(sizeof(uint8_t), max, max);
  ssize_t r = recv((int)fd, lean_sarray_cptr(ba), max, 0);
  if (r < 0)
  {
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
      lean_dec_ref(ba);
      lean_object *empty = lean_alloc_sarray(sizeof(uint8_t), 0, 0);
      return lean_io_result_mk_ok(empty);
    }
    lean_dec_ref(ba);
    return mk_io_error_from_errno(errno);
  }
  if (r == 0)
  {
    lean_dec_ref(ba);
    lean_object *empty = lean_alloc_sarray(sizeof(uint8_t), 0, 0);
    return lean_io_result_mk_ok(empty);
  }
  if ((size_t)r < max)
  {
    lean_object *ba2 = lean_alloc_sarray(sizeof(uint8_t), r, r);
    memcpy(lean_sarray_cptr(ba2), lean_sarray_cptr(ba), r);
    lean_dec_ref(ba);
    return lean_io_result_mk_ok(ba2);
  }
  return lean_io_result_mk_ok(ba);
}

lean_obj_res ws_set_nonblocking(uint32_t fd) {
  if (set_nonblocking((int)fd) < 0) return mk_io_error_from_errno(errno);
  return lean_io_result_mk_ok(lean_box(0));
}

lean_obj_res ws_send_bytes(uint32_t fd, lean_object *ba)
{
  size_t n = lean_sarray_size(ba);
  uint8_t *ptr = lean_sarray_cptr(ba);
  size_t total_sent = 0;
  while (total_sent < n) {
    ssize_t sent = send((int)fd, ptr + total_sent, n - total_sent, MSG_NOSIGNAL);
    if (sent < 0) {
      if (errno == EAGAIN || errno == EWOULDBLOCK)
        return lean_io_result_mk_ok(lean_box((unsigned)total_sent));
      return mk_io_error_from_errno(errno);
    }
    total_sent += (size_t)sent;
  }
  return lean_io_result_mk_ok(lean_box((unsigned)total_sent));
}

lean_obj_res ws_connect(b_lean_obj_arg host, uint32_t port) {
  const char *h = lean_string_cstr(host);
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  if (fd < 0) return mk_io_error_from_errno(errno);
  struct sockaddr_in addr; memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET; addr.sin_port = htons((uint16_t)port);
  if (inet_pton(AF_INET, h, &addr.sin_addr) <= 0) {
    struct hostent *he = gethostbyname(h);
    if (!he || he->h_addrtype != AF_INET) {
      int e = errno; close(fd); return mk_io_error_from_errno(e ? e : EINVAL);
    }
    memcpy(&addr.sin_addr, he->h_addr_list[0], sizeof(struct in_addr));
  }
  if (connect(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
    int e = errno; close(fd); return mk_io_error_from_errno(e);
  }
  set_nonblocking(fd);
  return lean_io_result_mk_ok(lean_box(fd));
}

// Using Linux getrandom exclusively for now.
lean_obj_res ws_random_bytes(size_t n) {
  lean_object *ba = lean_alloc_sarray(sizeof(uint8_t), n, n);
  ssize_t got = getrandom(lean_sarray_cptr(ba), n, 0);
  if (got < 0 || (size_t)got != n) {
    lean_dec_ref(ba);
    return lean_io_result_mk_error(lean_mk_string("random error"));
  }
  return lean_io_result_mk_ok(ba);
}

lean_obj_res ws_now_iso8601() {
  struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
  struct tm tmv; gmtime_r(&ts.tv_sec, &tmv);
  long ms = ts.tv_nsec / 1000000L;
  char buf[32];
  int n = snprintf(buf, sizeof(buf), "%04d-%02d-%02dT%02d:%02d:%02d.%03ldZ",
    tmv.tm_year + 1900, tmv.tm_mon + 1, tmv.tm_mday,
    tmv.tm_hour, tmv.tm_min, tmv.tm_sec, ms);
  if (n < 0) {
    return lean_io_result_mk_error(lean_mk_string("timestamp format error"));
  }
  return lean_io_result_mk_ok(lean_mk_string(buf));
}

end
