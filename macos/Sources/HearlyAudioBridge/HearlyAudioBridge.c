#include "HearlyAudioBridge.h"

#include <fcntl.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#define HEARLY_AUDIO_RING_NAME "/hearly-virtual-mic-v1"
#define HEARLY_AUDIO_RING_CAPACITY 16384u
#define HEARLY_AUDIO_RING_CHANNELS 2u

typedef struct {
    _Atomic uint32_t write_index;
    _Atomic uint32_t read_index;
    float samples[HEARLY_AUDIO_RING_CAPACITY * HEARLY_AUDIO_RING_CHANNELS];
} HearlyAudioRing;

static uint32_t ring_distance(uint32_t write_index, uint32_t read_index) {
    return write_index - read_index;
}

void *hearly_audio_ring_open(int create_if_missing) {
    int flags = O_RDWR;
    if (create_if_missing) {
        flags |= O_CREAT;
    }

    int descriptor = shm_open(HEARLY_AUDIO_RING_NAME, flags, 0600);
    if (descriptor < 0) {
        return NULL;
    }

    size_t byte_count = sizeof(HearlyAudioRing);
    if (create_if_missing && ftruncate(descriptor, (off_t)byte_count) != 0) {
        close(descriptor);
        return NULL;
    }

    void *mapping = mmap(NULL, byte_count, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0);
    close(descriptor);
    if (mapping == MAP_FAILED) {
        return NULL;
    }

    return mapping;
}

void hearly_audio_ring_close(void *ring) {
    if (ring != NULL) {
        munmap(ring, sizeof(HearlyAudioRing));
    }
}

uint32_t hearly_audio_ring_write(void *ring, const float *samples, uint32_t frame_count) {
    if (ring == NULL || samples == NULL || frame_count == 0) {
        return 0;
    }

    HearlyAudioRing *shared = (HearlyAudioRing *)ring;
    uint32_t write_index = atomic_load_explicit(&shared->write_index, memory_order_relaxed);
    uint32_t read_index = atomic_load_explicit(&shared->read_index, memory_order_acquire);
    uint32_t available = HEARLY_AUDIO_RING_CAPACITY - ring_distance(write_index, read_index);
    uint32_t frames_to_write = frame_count < available ? frame_count : available;

    for (uint32_t frame = 0; frame < frames_to_write; frame += 1) {
        uint32_t offset = ((write_index + frame) % HEARLY_AUDIO_RING_CAPACITY) * HEARLY_AUDIO_RING_CHANNELS;
        shared->samples[offset] = samples[frame * HEARLY_AUDIO_RING_CHANNELS];
        shared->samples[offset + 1] = samples[frame * HEARLY_AUDIO_RING_CHANNELS + 1];
    }

    atomic_store_explicit(&shared->write_index, write_index + frames_to_write, memory_order_release);
    return frames_to_write;
}

uint32_t hearly_audio_ring_read(void *ring, float *samples, uint32_t frame_count) {
    if (ring == NULL || samples == NULL || frame_count == 0) {
        return 0;
    }

    HearlyAudioRing *shared = (HearlyAudioRing *)ring;
    uint32_t read_index = atomic_load_explicit(&shared->read_index, memory_order_relaxed);
    uint32_t write_index = atomic_load_explicit(&shared->write_index, memory_order_acquire);
    uint32_t available = ring_distance(write_index, read_index);
    uint32_t frames_to_read = frame_count < available ? frame_count : available;

    for (uint32_t frame = 0; frame < frames_to_read; frame += 1) {
        uint32_t offset = ((read_index + frame) % HEARLY_AUDIO_RING_CAPACITY) * HEARLY_AUDIO_RING_CHANNELS;
        samples[frame * HEARLY_AUDIO_RING_CHANNELS] = shared->samples[offset];
        samples[frame * HEARLY_AUDIO_RING_CHANNELS + 1] = shared->samples[offset + 1];
    }

    for (uint32_t frame = frames_to_read; frame < frame_count; frame += 1) {
        samples[frame * HEARLY_AUDIO_RING_CHANNELS] = 0.0f;
        samples[frame * HEARLY_AUDIO_RING_CHANNELS + 1] = 0.0f;
    }

    atomic_store_explicit(&shared->read_index, read_index + frames_to_read, memory_order_release);
    return frames_to_read;
}

uint32_t hearly_audio_ring_available(void *ring) {
    if (ring == NULL) {
        return 0;
    }

    HearlyAudioRing *shared = (HearlyAudioRing *)ring;
    uint32_t write_index = atomic_load_explicit(&shared->write_index, memory_order_acquire);
    uint32_t read_index = atomic_load_explicit(&shared->read_index, memory_order_relaxed);
    return ring_distance(write_index, read_index);
}
