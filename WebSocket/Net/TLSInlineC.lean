/-
Experimental TLS (OpenSSL) FFI layer. If OpenSSL is unavailable, these functions will return errors.
The goal is to keep raw C separate from the baseline InlineC file to avoid parsing fragility.
-/
import Alloy.C
open scoped Alloy.C

alloy c section

#include <lean/lean.h>
#include <string.h>

#ifdef WEBSOCKET_TLS
  #include <openssl/ssl.h>
  #include <openssl/err.h>

  static lean_object *mk_tls_err() {
    unsigned long e = ERR_get_error();
    if (e == 0) return lean_io_result_mk_error(lean_mk_string("tls error"));
    char buf[256];
    ERR_error_string_n(e, buf, sizeof(buf));
    return lean_io_result_mk_error(lean_mk_string(buf));
  }

  lean_obj_res ws_tls_init_ctx(b_lean_obj_arg certFile, b_lean_obj_arg keyFile) {
    const char *cert = lean_string_cstr(certFile);
    const char *key = lean_string_cstr(keyFile);
    SSL_CTX *ctx = SSL_CTX_new(TLS_server_method());
    if (!ctx) return mk_tls_err();
    SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION);
    if (SSL_CTX_use_certificate_file(ctx, cert, SSL_FILETYPE_PEM) <= 0) { SSL_CTX_free(ctx); return mk_tls_err(); }
    if (SSL_CTX_use_PrivateKey_file(ctx, key, SSL_FILETYPE_PEM) <= 0) { SSL_CTX_free(ctx); return mk_tls_err(); }
    if (!SSL_CTX_check_private_key(ctx)) { SSL_CTX_free(ctx); return mk_tls_err(); }
    return lean_io_result_mk_ok(lean_box((uint64_t)ctx));
  }

  lean_obj_res ws_tls_accept(uint64_t ctxPtr, uint32_t fd) {
    SSL_CTX *ctx = (SSL_CTX*)ctxPtr;
    SSL *ssl = SSL_new(ctx);
    if (!ssl) return mk_tls_err();
    SSL_set_fd(ssl, (int)fd);
    int r = SSL_accept(ssl);
    if (r <= 0) { SSL_free(ssl); return mk_tls_err(); }
    return lean_io_result_mk_ok(lean_box((uint64_t)ssl));
  }

  lean_obj_res ws_tls_read(uint64_t sslPtr, size_t max) {
    SSL *ssl = (SSL*)sslPtr;
    if (max == 0) max = 1; if (max > 65536) max = 65536;
    lean_object *ba = lean_alloc_sarray(sizeof(uint8_t), max, max);
    int r = SSL_read(ssl, lean_sarray_cptr(ba), (int)max);
    if (r <= 0) {
      int err = SSL_get_error(ssl, r);
      if (err == SSL_ERROR_WANT_READ || err == SSL_ERROR_WANT_WRITE) {
        lean_dec_ref(ba);
        lean_object *empty = lean_alloc_sarray(sizeof(uint8_t),0,0);
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
    SSL *ssl = (SSL*)sslPtr;
    int r = SSL_write(ssl, lean_sarray_cptr(ba), (int)lean_sarray_size(ba));
    if (r <= 0) {
      int err = SSL_get_error(ssl, r);
      if (err == SSL_ERROR_WANT_READ || err == SSL_ERROR_WANT_WRITE) {
        return lean_io_result_mk_ok(lean_box(0));
      }
      return mk_tls_err();
    }
    return lean_io_result_mk_ok(lean_box((unsigned)r));
  }

  lean_obj_res ws_tls_close(uint64_t sslPtr) {
    SSL *ssl = (SSL*)sslPtr;
    SSL_shutdown(ssl);
    SSL_free(ssl);
    return lean_io_result_mk_ok(lean_box(0));
  }

#else
  // Stubs when TLS disabled at build time.
  static lean_object *tls_disabled_err() {
    return lean_io_result_mk_error(lean_mk_string("tls disabled"));
  }
  lean_obj_res ws_tls_init_ctx(b_lean_obj_arg certFile, b_lean_obj_arg keyFile) { (void)certFile; (void)keyFile; return tls_disabled_err(); }
  lean_obj_res ws_tls_accept(uint64_t ctxPtr, uint32_t fd) { (void)ctxPtr; (void)fd; return tls_disabled_err(); }
  lean_obj_res ws_tls_read(uint64_t sslPtr, size_t max) { (void)sslPtr; (void)max; return tls_disabled_err(); }
  lean_obj_res ws_tls_write(uint64_t sslPtr, lean_object *ba) { (void)sslPtr; (void)ba; return tls_disabled_err(); }
  lean_obj_res ws_tls_close(uint64_t sslPtr) { (void)sslPtr; return tls_disabled_err(); }
#endif

end
