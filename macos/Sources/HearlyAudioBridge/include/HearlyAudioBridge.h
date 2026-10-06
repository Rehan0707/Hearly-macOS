#ifndef HEARLY_AUDIO_BRIDGE_H
#define HEARLY_AUDIO_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void *hearly_audio_ring_open(int create_if_missing);
void hearly_audio_ring_close(void *ring);
uint32_t hearly_audio_ring_write(void *ring, const float *samples, uint32_t frame_count);
uint32_t hearly_audio_ring_read(void *ring, float *samples, uint32_t frame_count);
uint32_t hearly_audio_ring_available(void *ring);

#ifdef __cplusplus
}
#endif

#endif
