#ifndef HEARLY_LOOPBACK_H
#define HEARLY_LOOPBACK_H
#include <stdatomic.h>
#include <stdint.h>
#include <string.h>

#define HEARLY_LOOPBACK_CAPACITY 16384u
#define HEARLY_LOOPBACK_DELAY 480u

/// Shared only inside Core Audio's driver process, never through POSIX shm.
/// Each frame has a sample-time tag; missing/old frames are silence, not replay.
typedef struct {
    _Atomic uint64_t tags[HEARLY_LOOPBACK_CAPACITY];
    _Atomic uint32_t samples[HEARLY_LOOPBACK_CAPACITY * 2];
} HearlyLoopback;

static inline void hearly_loopback_write(HearlyLoopback *ring, uint64_t time, const float *samples, uint32_t frames) {
    for (uint32_t frame = 0; frame < frames; ++frame) {
        uint64_t sample_time = time + frame;
        uint32_t index = (uint32_t)(sample_time % HEARLY_LOOPBACK_CAPACITY);
        // Invalidate before writing either channel. Atomic samples avoid a data
        // race even when a very late reader crosses a wrapped slot.
        atomic_store_explicit(&ring->tags[index], 0, memory_order_release);
        for (uint32_t channel = 0; channel < 2; ++channel) {
            uint32_t bits;
            memcpy(&bits, &samples[frame * 2 + channel], sizeof(bits));
            atomic_store_explicit(&ring->samples[index * 2 + channel], bits, memory_order_relaxed);
        }
        atomic_store_explicit(&ring->tags[index], sample_time + 1, memory_order_release);
    }
}

static inline void hearly_loopback_read(HearlyLoopback *ring, int64_t time, float *samples, uint32_t frames) {
    memset(samples, 0, sizeof(float) * frames * 2);
    for (uint32_t frame = 0; frame < frames; ++frame) {
        int64_t sample_time = time + frame;
        if (sample_time < 0) continue;
        uint32_t index = (uint32_t)((uint64_t)sample_time % HEARLY_LOOPBACK_CAPACITY);
        uint64_t expected = (uint64_t)sample_time + 1;
        if (atomic_load_explicit(&ring->tags[index], memory_order_acquire) != expected) continue;
        uint32_t left = atomic_load_explicit(&ring->samples[index * 2], memory_order_relaxed);
        uint32_t right = atomic_load_explicit(&ring->samples[index * 2 + 1], memory_order_relaxed);
        if (atomic_load_explicit(&ring->tags[index], memory_order_acquire) != expected) continue;
        memcpy(&samples[frame * 2], &left, sizeof(left));
        memcpy(&samples[frame * 2 + 1], &right, sizeof(right));
    }
}
#endif
