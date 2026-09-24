#ifndef GPUIDART_H
#define GPUIDART_H
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct Host GdHost;
typedef void (*GdEventCallback)(uint8_t *bytes, size_t len);

/* Returns NULL for an invalid initial description. Input bytes are copied.
   Callback owns each delivered buffer and must call gd_free_event exactly once. */
GdHost *gd_create(const uint8_t *bytes, size_t len, GdEventCallback callback);

/* Blocks on the calling thread until the native application closes. Call once. */
int32_t gd_run(const GdHost *host);

/* 0 = queued, -1 = invalid pointer/size, -2 = invalid description,
   -3 = queue closed or full. The applied event acknowledges native application. */
int32_t gd_publish(const GdHost *host, const uint8_t *bytes, size_t len);
void gd_close(const GdHost *host);

/* Wait for gd_run to return and the closed callback before destroying the host
   or releasing the callback. No other host API call may be in flight. */
void gd_destroy(GdHost *host);
void gd_free_event(uint8_t *bytes, size_t len);

#ifdef __cplusplus
}
#endif
#endif
