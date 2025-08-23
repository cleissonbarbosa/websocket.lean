// Minimal socket + Lean ByteArray bridging.
#include <unistd.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <string.h>
#include <errno.h>
#include <stdlib.h>
#include <lean/lean.h>

// Helper to set non-blocking mode
static int set_nonblocking(int fd) {
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags < 0) return -1;
  if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) return -1;
  return 0;
}

static lean_object *mk_io_error_from_errno(int err)
{
  lean_object *msg = lean_mk_string(errno == 0 ? "socket error" : strerror(err));
  return lean_io_result_mk_error(msg);
}

lean_obj_res ws_listen(int port)
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
  addr.sin_port = htons(port);
  if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0)
  {
    int e = errno;
    close(fd);
    return mk_io_error_from_errno(e);
  }
  if (listen(fd, 16) < 0)
  {
    int e = errno;
    close(fd);
    return mk_io_error_from_errno(e);
  }
  // Set listening socket non-blocking (best effort)
  set_nonblocking(fd);
  return lean_io_result_mk_ok(lean_box(fd));
}

lean_obj_res ws_accept(int listen_fd)
{
  int cfd = accept(listen_fd, NULL, NULL);
  if (cfd < 0)
    return mk_io_error_from_errno(errno);
  set_nonblocking(cfd);
  return lean_io_result_mk_ok(lean_box(cfd));
}

lean_obj_res ws_close(int fd)
{
  if (close(fd) < 0)
    return mk_io_error_from_errno(errno);
  return lean_io_result_mk_ok(lean_box(0));
}

lean_obj_res ws_recv_bytes(int fd, size_t max)
{
  if (max == 0)
    max = 1;
  if (max > 65536)
    max = 65536;
  lean_object *ba = lean_alloc_sarray(sizeof(uint8_t), max, max);
  ssize_t r = recv(fd, lean_sarray_cptr(ba), max, 0);
  if (r < 0)
  {
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
      // No data available now -> return empty (non-blocking semantics)
      lean_dec_ref(ba);
      lean_object *empty = lean_alloc_sarray(sizeof(uint8_t), 0, 0);
      return lean_io_result_mk_ok(empty);
    }
    lean_dec_ref(ba);
    return mk_io_error_from_errno(errno);
  }
  if (r == 0)
  { // EOF -> return empty
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

// Exposed function to force non-blocking (optional from Lean)
lean_obj_res ws_set_nonblocking(int fd) {
  if (set_nonblocking(fd) < 0) return mk_io_error_from_errno(errno);
  return lean_io_result_mk_ok(lean_box(0));
}

lean_obj_res ws_send_bytes(int fd, lean_object *ba)
{
  size_t n = lean_sarray_size(ba);
  ssize_t sent = send(fd, lean_sarray_cptr(ba), n, 0);
  if (sent < 0)
    return mk_io_error_from_errno(errno);
  return lean_io_result_mk_ok(lean_box((unsigned)sent));
}
