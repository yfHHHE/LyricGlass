#include "PetAudio.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <math.h>

struct LGLevelMeter { _Atomic(float) level; };
LGLevelMeter *LGLevelMeterCreate(void) {
    LGLevelMeter *meter = calloc(1, sizeof(LGLevelMeter));
    if (meter) atomic_init(&meter->level, 0);
    return meter;
}
void LGLevelMeterDestroy(LGLevelMeter *meter) { free(meter); }
float LGLevelMeterRead(LGLevelMeter *meter) {
    return meter ? atomic_load_explicit(&meter->level, memory_order_relaxed) : 0;
}
void LGLevelMeterMeasure(LGLevelMeter *meter, const AudioBufferList *buffers) {
    if (!meter || !buffers) return;
    double energy = 0; size_t count = 0;
    for (UInt32 b = 0; b < buffers->mNumberBuffers; b++) {
        const AudioBuffer *buffer = &buffers->mBuffers[b];
        if (!buffer->mData) continue;
        const float *samples = buffer->mData;
        size_t n = buffer->mDataByteSize / sizeof(float);
        for (size_t i = 0; i < n; i++) {
            float sample = samples[i];
            if (isfinite(sample)) { energy += (double)sample * sample; count++; }
        }
    }
    atomic_store_explicit(&meter->level, count ? fminf(1, sqrt(energy / count)) : 0, memory_order_relaxed);
}
OSStatus LGLevelMeterIOProc(AudioObjectID device, const AudioTimeStamp *now,
    const AudioBufferList *input, const AudioTimeStamp *inputTime,
    AudioBufferList *output, const AudioTimeStamp *outputTime, void *context) {
    if (context) LGLevelMeterMeasure(context, input);
    return noErr;
}
