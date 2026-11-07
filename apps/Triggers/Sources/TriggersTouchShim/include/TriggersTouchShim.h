// The contact record MultitouchSupport.framework (private) hands to frame callbacks.
// Layout from long-standing open-source readers (OpenMultitouchSupport, MiddleClick), checked
// on macOS 27.2 (docs/research/triggers.md, spikes). Only TouchSource.swift uses it.
#ifndef TRIGGERS_TOUCH_SHIM_H
#define TRIGGERS_TOUCH_SHIM_H

#include <stdint.h>

typedef struct { float x; float y; } TRTouchPoint;
typedef struct { TRTouchPoint position; TRTouchPoint velocity; } TRTouchVector;

typedef struct {
    int32_t frame;
    double timestamp;
    int32_t identifier;
    int32_t state;            // 0 not tracking … 3 make touch, 4 touching, 5 break touch … 7 out of range
    int32_t fingerID;
    int32_t handID;
    TRTouchVector normalized; // 0…1, origin bottom left
    float total;              // capacitance total: contact size
    float pressure;
    float angle;
    float majorAxis;
    float minorAxis;
    TRTouchVector absolute;   // millimetres
    int32_t field14;
    int32_t field15;
    float density;
} TRTouch;

_Static_assert(sizeof(TRTouch) == 96, "MultitouchSupport contact layout changed");

typedef void *TRTouchDeviceRef;
typedef void (*TRTouchFrameCallback)(TRTouchDeviceRef device, const TRTouch *touches, int32_t count, double timestamp, int32_t frame);

#endif
