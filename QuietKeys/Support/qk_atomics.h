// qk_atomics.h — C11 atomic helpers for the lock-free audio trigger ring.
// Swift has no stable freestanding atomics without a package dependency;
// these inline functions give acquire/release semantics for the SPSC ring.

#ifndef QK_ATOMICS_H
#define QK_ATOMICS_H

#include <stdatomic.h>
#include <stdint.h>

typedef struct {
    _Atomic uint64_t value;
} qk_atomic_u64;

static inline void qk_store_release(qk_atomic_u64 *a, uint64_t v) {
    atomic_store_explicit(&a->value, v, memory_order_release);
}

static inline uint64_t qk_load_acquire(const qk_atomic_u64 *a) {
    return atomic_load_explicit(&((qk_atomic_u64 *)a)->value, memory_order_acquire);
}

static inline void qk_store_relaxed(qk_atomic_u64 *a, uint64_t v) {
    atomic_store_explicit(&a->value, v, memory_order_relaxed);
}

static inline uint64_t qk_load_relaxed(const qk_atomic_u64 *a) {
    return atomic_load_explicit(&((qk_atomic_u64 *)a)->value, memory_order_relaxed);
}

#endif /* QK_ATOMICS_H */
