/-
Runtime TLS (OpenSSL) FFI layer using dlopen.

OpenSSL is loaded dynamically at runtime — no compile-time toggle or link-time
dependency on libssl/libcrypto is required. If OpenSSL is not installed on the
system, TLS functions return a descriptive error; everything else keeps working.

To enable TLS at runtime, just install OpenSSL (e.g. `apt install libssl-dev`)
or point `LD_LIBRARY_PATH` to a directory containing `libssl.so` + `libcrypto.so`.
No rebuild needed.
-/
import Alloy.C
open scoped Alloy.C

alloy c section

#include <lean/lean.h>
#include <string.h>
#include <dlfcn.h>
#include <stdint.h>

/* ── OpenSSL constants (stable across 1.1 / 3.x) ─────────────────────────── */
#define WS_TLS1_2_VERSION    0x0303
#define WS_SSL_FILETYPE_PEM  1
#define WS_SSL_ERROR_WANT_READ  2
#define WS_SSL_ERROR_WANT_WRITE 3
#define WS_SSL_CTRL_SET_MIN_PROTO_VERSION 123

#define WS_DLSYM(handle, sym) \
  ossl.sym = (pfn_##sym)dlsym(ossl.handle, #sym); \
  if (!ossl.sym) goto fail

/* ── Function-pointer typedefs matching the OpenSSL public API ────────────── */
typedef void *(*pfn_TLS_server_method)(void);
typedef void *(*pfn_SSL_CTX_new)(const void *);
typedef long  (*pfn_SSL_CTX_ctrl)(void *, int, long, void *);
typedef int   (*pfn_SSL_CTX_use_certificate_file)(void *, const char *, int);
typedef int   (*pfn_SSL_CTX_use_PrivateKey_file)(void *, const char *, int);
typedef int   (*pfn_SSL_CTX_check_private_key)(const void *);
typedef void  (*pfn_SSL_CTX_free)(void *);
typedef void *(*pfn_SSL_new)(void *);
typedef int   (*pfn_SSL_set_fd)(void *, int);
typedef int   (*pfn_SSL_accept)(void *);
typedef int   (*pfn_SSL_read)(void *, void *, int);
typedef int   (*pfn_SSL_write)(void *, const void *, int);
typedef int   (*pfn_SSL_get_error)(const void *, int);
typedef int   (*pfn_SSL_shutdown)(void *);
typedef void  (*pfn_SSL_free)(void *);
typedef unsigned long (*pfn_ERR_get_error)(void);
typedef void  (*pfn_ERR_error_string_n)(unsigned long, char *, size_t);

/* ── Lazy-loaded symbol table ─────────────────────────────────────────────── */
static struct {
  void *libssl;
  void *libcrypto;
  int loaded;
  int attempted;
  pfn_TLS_server_method             TLS_server_method;
  pfn_SSL_CTX_new                   SSL_CTX_new;
  pfn_SSL_CTX_ctrl                  SSL_CTX_ctrl;
  pfn_SSL_CTX_use_certificate_file  SSL_CTX_use_certificate_file;
  pfn_SSL_CTX_use_PrivateKey_file   SSL_CTX_use_PrivateKey_file;
  pfn_SSL_CTX_check_private_key     SSL_CTX_check_private_key;
  pfn_SSL_CTX_free                  SSL_CTX_free;
  pfn_SSL_new                       SSL_new;
  pfn_SSL_set_fd                    SSL_set_fd;
  pfn_SSL_accept                    SSL_accept;
  pfn_SSL_read                      SSL_read;
  pfn_SSL_write                     SSL_write;
  pfn_SSL_get_error                 SSL_get_error;
  pfn_SSL_shutdown                  SSL_shutdown;
  pfn_SSL_free                      SSL_free;
  pfn_ERR_get_error                 ERR_get_error;
  pfn_ERR_error_string_n            ERR_error_string_n;
} ossl = {0};

static int ensure_openssl(void) {
  if (ossl.attempted) return ossl.loaded;
  ossl.attempted = 1;

  /* libcrypto must be opened first (libssl depends on it) */
  static const char *crypto_names[] = {
    "libcrypto.so", "libcrypto.so.3", "libcrypto.so.1.1",
    "libcrypto.dylib", "libcrypto.3.dylib", "libcrypto.1.1.dylib",
    NULL};
  static const char *ssl_names[] = {
    "libssl.so", "libssl.so.3", "libssl.so.1.1",
    "libssl.dylib", "libssl.3.dylib", "libssl.1.1.dylib",
    NULL};

  for (const char **p = crypto_names; *p; ++p) {
    ossl.libcrypto = dlopen(*p, RTLD_NOW | RTLD_GLOBAL);
    if (ossl.libcrypto) break;
  }
  if (!ossl.libcrypto) return 0;

  for (const char **p = ssl_names; *p; ++p) {
    ossl.libssl = dlopen(*p, RTLD_NOW | RTLD_GLOBAL);
    if (ossl.libssl) break;
  }
  if (!ossl.libssl) { dlclose(ossl.libcrypto); ossl.libcrypto = NULL; return 0; }

  WS_DLSYM(libssl,    TLS_server_method);
  WS_DLSYM(libssl,    SSL_CTX_new);
  WS_DLSYM(libssl,    SSL_CTX_ctrl);
  WS_DLSYM(libssl,    SSL_CTX_use_certificate_file);
  WS_DLSYM(libssl,    SSL_CTX_use_PrivateKey_file);
  WS_DLSYM(libssl,    SSL_CTX_check_private_key);
  WS_DLSYM(libssl,    SSL_CTX_free);
  WS_DLSYM(libssl,    SSL_new);
  WS_DLSYM(libssl,    SSL_set_fd);
  WS_DLSYM(libssl,    SSL_accept);
  WS_DLSYM(libssl,    SSL_read);
  WS_DLSYM(libssl,    SSL_write);
  WS_DLSYM(libssl,    SSL_get_error);
  WS_DLSYM(libssl,    SSL_shutdown);
  WS_DLSYM(libssl,    SSL_free);
  WS_DLSYM(libcrypto, ERR_get_error);
  WS_DLSYM(libcrypto, ERR_error_string_n);

  ossl.loaded = 1;
  return 1;

fail:
  if (ossl.libssl)    { dlclose(ossl.libssl);    ossl.libssl    = NULL; }
  if (ossl.libcrypto) { dlclose(ossl.libcrypto); ossl.libcrypto = NULL; }
  return 0;
}

/* ── Error helpers ────────────────────────────────────────────────────────── */

static lean_object *mk_tls_unavailable(void) {
  return lean_io_result_mk_error(
    lean_mk_io_user_error(lean_mk_string(
      "TLS unavailable: OpenSSL not found (install libssl-dev or openssl)")));
}

static lean_object *mk_tls_err(void) {
  unsigned long e = ossl.ERR_get_error();
  if (e == 0)
    return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string("tls error")));
  char buf[256];
  ossl.ERR_error_string_n(e, buf, sizeof(buf));
  return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string(buf)));
}

/* ── Lean FFI functions ───────────────────────────────────────────────────── */

lean_obj_res ws_tls_available(lean_obj_arg unit) {
  (void)unit;
  return lean_io_result_mk_ok(lean_box(ensure_openssl() ? 1 : 0));
}

lean_obj_res ws_tls_init_ctx(b_lean_obj_arg certFile, b_lean_obj_arg keyFile) {
  if (!ensure_openssl()) return mk_tls_unavailable();
  const char *cert = lean_string_cstr(certFile);
  const char *key  = lean_string_cstr(keyFile);
  void *ctx = ossl.SSL_CTX_new(ossl.TLS_server_method());
  if (!ctx) return mk_tls_err();
  ossl.SSL_CTX_ctrl(ctx, WS_SSL_CTRL_SET_MIN_PROTO_VERSION, WS_TLS1_2_VERSION, NULL);
  if (ossl.SSL_CTX_use_certificate_file(ctx, cert, WS_SSL_FILETYPE_PEM) <= 0)
    { ossl.SSL_CTX_free(ctx); return mk_tls_err(); }
  if (ossl.SSL_CTX_use_PrivateKey_file(ctx, key, WS_SSL_FILETYPE_PEM) <= 0)
    { ossl.SSL_CTX_free(ctx); return mk_tls_err(); }
  if (!ossl.SSL_CTX_check_private_key(ctx))
    { ossl.SSL_CTX_free(ctx); return mk_tls_err(); }
  return lean_io_result_mk_ok(lean_box_uint64((uint64_t)(uintptr_t)ctx));
}

lean_obj_res ws_tls_accept(uint64_t ctxPtr, uint32_t fd) {
  if (!ensure_openssl()) return mk_tls_unavailable();
  void *ctx = (void *)(uintptr_t)ctxPtr;
  void *ssl = ossl.SSL_new(ctx);
  if (!ssl) return mk_tls_err();
  ossl.SSL_set_fd(ssl, (int)fd);
  int r = ossl.SSL_accept(ssl);
  if (r <= 0) { ossl.SSL_free(ssl); return mk_tls_err(); }
  return lean_io_result_mk_ok(lean_box_uint64((uint64_t)(uintptr_t)ssl));
}

lean_obj_res ws_tls_read(uint64_t sslPtr, uint32_t max) {
  if (!ensure_openssl()) return mk_tls_unavailable();
  void *ssl = (void *)(uintptr_t)sslPtr;
  if (max == 0) max = 1;
  if (max > 65536) max = 65536;
  lean_object *ba = lean_alloc_sarray(sizeof(uint8_t), max, max);
  int r = ossl.SSL_read(ssl, lean_sarray_cptr(ba), (int)max);
  if (r <= 0) {
    int err = ossl.SSL_get_error(ssl, r);
    if (err == WS_SSL_ERROR_WANT_READ || err == WS_SSL_ERROR_WANT_WRITE) {
      lean_dec_ref(ba);
      lean_object *empty = lean_alloc_sarray(sizeof(uint8_t), 0, 0);
      return lean_io_result_mk_ok(empty);
    }
    lean_dec_ref(ba);
    return mk_tls_err();
  }
  if ((size_t)r < max) {
    lean_object *ba2 = lean_alloc_sarray(sizeof(uint8_t), r, r);
    memcpy(lean_sarray_cptr(ba2), lean_sarray_cptr(ba), r);
    lean_dec_ref(ba);
    return lean_io_result_mk_ok(ba2);
  }
  return lean_io_result_mk_ok(ba);
}

lean_obj_res ws_tls_write(uint64_t sslPtr, lean_object *ba) {
  if (!ensure_openssl()) return mk_tls_unavailable();
  void *ssl = (void *)(uintptr_t)sslPtr;
  int r = ossl.SSL_write(ssl, lean_sarray_cptr(ba), (int)lean_sarray_size(ba));
  if (r <= 0) {
    int err = ossl.SSL_get_error(ssl, r);
    if (err == WS_SSL_ERROR_WANT_READ || err == WS_SSL_ERROR_WANT_WRITE) {
      return lean_io_result_mk_ok(lean_box(0));
    }
    return mk_tls_err();
  }
  return lean_io_result_mk_ok(lean_box((unsigned)r));
}

lean_obj_res ws_tls_close(uint64_t sslPtr) {
  if (!ossl.loaded) return lean_io_result_mk_ok(lean_box(0));
  void *ssl = (void *)(uintptr_t)sslPtr;
  ossl.SSL_shutdown(ssl);
  ossl.SSL_free(ssl);
  return lean_io_result_mk_ok(lean_box(0));
}

end
