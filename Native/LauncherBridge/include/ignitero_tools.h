#ifndef IGNITERO_TOOLS_H
#define IGNITERO_TOOLS_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct IgniteroJob IgniteroJob;
/* Version 1: kind 1 = {"refresh":false}, kind 2 = {"url":"https://example.com"}.
   UTF-8 strings are NUL terminated. out_error must be non-NULL and initially NULL.
   out_status is required: 0 started, 1 invalid/error, 2 busy.
   Only one active job of each kind is allowed. No credentials enter this ABI. */
IgniteroJob *ignitero_job_start(uint32_t kind, const char *request, int32_t *out_status, char **out_error);
/* 0 pending, 1 ready (owned UTF-8 JSON in out_json), -1 invalid/previously taken.
   JSON envelope: {"schema_version":1,"data":...} or {"schema_version":1,"error":...}.
   Poll/take calls on a handle must be serialized. */
int32_t ignitero_job_poll(IgniteroJob *job, char **out_json);
int32_t ignitero_job_busy(uint32_t kind);
/* cancel is thread-safe while the handle is alive. free cancels and returns without
   joining the worker. Free exactly once, after every poll/cancel call has returned. */
void ignitero_job_cancel(IgniteroJob *job);
void ignitero_job_free(IgniteroJob *job);
void ignitero_string_free(char *value);
#ifdef __cplusplus
}
#endif
#endif
