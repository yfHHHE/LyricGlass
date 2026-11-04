#pragma once
#include <CoreAudio/CoreAudio.h>
#pragma clang assume_nonnull begin
typedef struct LGLevelMeter LGLevelMeter;
LGLevelMeter * _Nullable LGLevelMeterCreate(void);
void LGLevelMeterDestroy(LGLevelMeter *meter);
float LGLevelMeterRead(LGLevelMeter *meter);
// Only native-endian Float32 PCM is accepted by the Swift setup code.
void LGLevelMeterMeasure(LGLevelMeter *meter, const AudioBufferList *buffers);
OSStatus LGLevelMeterIOProc(AudioObjectID device, const AudioTimeStamp *now,
    const AudioBufferList *input, const AudioTimeStamp *inputTime,
    AudioBufferList *output, const AudioTimeStamp *outputTime, void * _Nullable context);
#pragma clang assume_nonnull end
