#include "PetAudio.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
int main(void) {
    LGLevelMeter *meter = LGLevelMeterCreate(); assert(meter);
    float data[] = {0.5f, -0.5f, 0.5f, -0.5f};
    AudioBufferList input = { .mNumberBuffers = 1, .mBuffers = {{ .mNumberChannels = 2, .mDataByteSize = sizeof(data), .mData = data }} };
    LGLevelMeterMeasure(meter, &input);
    assert(fabsf(LGLevelMeterRead(meter) - 0.5f) < 0.0001f);
    for (int i = 0; i < 4; i++) data[i] = 0;
    LGLevelMeterMeasure(meter, &input); assert(LGLevelMeterRead(meter) == 0);
    data[0] = NAN; data[1] = INFINITY;
    LGLevelMeterMeasure(meter, &input); assert(isfinite(LGLevelMeterRead(meter)));
    LGLevelMeterDestroy(meter);
    puts("PASS realtime PCM meter: stereo RMS, silence, nonfinite samples; no audio capture");
}
