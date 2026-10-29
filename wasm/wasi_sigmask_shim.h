/* Force-included (-include) into the WASI build of prjuray-tools only.
 * The abseil prjuray vendors masks every signal around pthread_setspecific
 * (absl/base/internal/thread_identity.cc), guarded only for Emscripten and
 * MinGW. WASI declares none of sigfillset, pthread_sigmask or SIG_SETMASK:
 * it has no signals and one thread, so masking is a no-op. */
#ifndef WASI_SIGMASK_SHIM_H
#define WASI_SIGMASK_SHIM_H
#if defined(__wasi__)
#include <signal.h>
#define __NEED_sigset_t /* as libc's own headers get it, without _POSIX_SOURCE */
#include <bits/alltypes.h>
#ifndef SIG_SETMASK
#define SIG_SETMASK 2
static inline int sigfillset(sigset_t *s) { (void)s; return 0; }
static inline int pthread_sigmask(int how, const sigset_t *set, sigset_t *old)
{
    (void)how; (void)set;
    if (old) __builtin_memset(old, 0, sizeof *old);
    return 0;
}
#endif
#endif
#endif
