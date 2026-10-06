#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreAudio/AudioHardware.h>
#include <CoreAudio/AudioHardwareBase.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <stddef.h>
#include <string.h>

#include "HearlyLoopback.h"

#define HEARLY_PLUGIN_OBJECT 1
#define HEARLY_DEVICE_OBJECT 2
#define HEARLY_STREAM_OBJECT 3
#define HEARLY_ELEMENT_OBJECT 4
#define HEARLY_OUTPUT_STREAM_OBJECT 5
#define HEARLY_SAMPLE_RATE 48000.0
#define HEARLY_BUFFER_FRAMES 480u
#define HEARLY_CHANNELS 2u

typedef struct {
    AudioServerPlugInDriverInterface interface;
    UInt32 reference_count;
    AudioServerPlugInHostRef host;
    HearlyLoopback loopback;
    UInt64 anchor_host_time;
    UInt64 sample_time;
    UInt64 seed;
    UInt32 running_clients;
} HearlyDriver;

static HearlyDriver g_driver;
static AudioServerPlugInDriverInterface *g_interface = &g_driver.interface;

static HearlyDriver *driver_state(AudioServerPlugInDriverRef driver) {
    if (driver == NULL || *driver == NULL) {
        return &g_driver;
    }
    return (HearlyDriver *)((char *)(*driver) - offsetof(HearlyDriver, interface));
}

static OSStatus copy_value(const void *value, UInt32 value_size, UInt32 data_size, UInt32 *out_size, void *out_data) {
    if (data_size < value_size || out_data == NULL) {
        return kAudioHardwareBadPropertySizeError;
    }
    memcpy(out_data, value, value_size);
    if (out_size != NULL) {
        *out_size = value_size;
    }
    return noErr;
}

static OSStatus copy_string(CFStringRef value, UInt32 data_size, UInt32 *out_size, void *out_data) {
    CFStringRef copy = CFStringCreateCopy(kCFAllocatorDefault, value);
    if (copy == NULL) {
        return kAudioHardwareUnspecifiedError;
    }
    OSStatus status = copy_value(&copy, sizeof(copy), data_size, out_size, out_data);
    if (status != noErr) {
        CFRelease(copy);
    }
    return status;
}

static AudioStreamBasicDescription stream_format(void) {
    AudioStreamBasicDescription format;
    memset(&format, 0, sizeof(format));
    format.mSampleRate = HEARLY_SAMPLE_RATE;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
    format.mBytesPerPacket = sizeof(Float32) * HEARLY_CHANNELS;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = sizeof(Float32) * HEARLY_CHANNELS;
    format.mChannelsPerFrame = HEARLY_CHANNELS;
    format.mBitsPerChannel = sizeof(Float32) * 8;
    return format;
}

static Boolean is_object(AudioObjectID object_id) {
    return object_id == HEARLY_PLUGIN_OBJECT || object_id == HEARLY_DEVICE_OBJECT || object_id == HEARLY_STREAM_OBJECT || object_id == HEARLY_OUTPUT_STREAM_OBJECT;
}

static Boolean has_property(AudioObjectID object_id, const AudioObjectPropertyAddress *address) {
    if (address == NULL || !is_object(object_id)) {
        return false;
    }

    switch (address->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyModelName:
        case kAudioObjectPropertyManufacturer:
        case kAudioObjectPropertyOwnedObjects:
            return true;
        default:
            break;
    }

    if (object_id == HEARLY_PLUGIN_OBJECT) {
        return address->mSelector == kAudioPlugInPropertyDeviceList || address->mSelector == kAudioPlugInPropertyTranslateUIDToDevice;
    }

    if (object_id == HEARLY_DEVICE_OBJECT) {
        switch (address->mSelector) {
            case kAudioDevicePropertyDeviceUID:
            case kAudioDevicePropertyModelUID:
            case kAudioDevicePropertyTransportType:
            case kAudioDevicePropertyDeviceIsAlive:
            case kAudioDevicePropertyDeviceIsRunning:
            case kAudioDevicePropertyNominalSampleRate:
            case kAudioDevicePropertyAvailableNominalSampleRates:
            case kAudioDevicePropertyBufferFrameSize:
            case kAudioDevicePropertyBufferFrameSizeRange:
            case kAudioDevicePropertyUsesVariableBufferFrameSizes:
            case kAudioDevicePropertyStreamConfiguration:
            case kAudioDevicePropertyStreams:
            case kAudioDevicePropertySafetyOffset:
            case kAudioDevicePropertyZeroTimeStampPeriod:
            case kAudioDevicePropertyClockDomain:
            case kAudioDevicePropertyDeviceCanBeDefaultDevice:
            case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
            case kAudioDevicePropertyPreferredChannelsForStereo:
            case kAudioDevicePropertyLatency:
                return true;
            default:
                return false;
        }
    }

    if (object_id == HEARLY_STREAM_OBJECT || object_id == HEARLY_OUTPUT_STREAM_OBJECT) {
        switch (address->mSelector) {
            case kAudioStreamPropertyIsActive:
            case kAudioStreamPropertyDirection:
            case kAudioStreamPropertyTerminalType:
            case kAudioStreamPropertyStartingChannel:
            case kAudioStreamPropertyLatency:
            case kAudioStreamPropertyVirtualFormat:
            case kAudioStreamPropertyAvailableVirtualFormats:
            case kAudioStreamPropertyPhysicalFormat:
            case kAudioStreamPropertyAvailablePhysicalFormats:
                return true;
            default:
                return false;
        }
    }

    return false;
}

static ULONG driver_add_ref(void *driver) {
    HearlyDriver *state = driver_state((AudioServerPlugInDriverRef)driver);
    return ++state->reference_count;
}

static ULONG driver_release(void *driver) {
    HearlyDriver *state = driver_state((AudioServerPlugInDriverRef)driver);
    if (state->reference_count > 0) {
        state->reference_count -= 1;
    }
    return state->reference_count;
}

static HRESULT driver_query_interface(void *driver, REFIID uuid, LPVOID *out_interface) {
    if (out_interface == NULL) {
        return E_NOINTERFACE;
    }
    *out_interface = NULL;
    CFUUIDRef requested_uuid = CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, uuid);
    if (requested_uuid == NULL) {
        return E_NOINTERFACE;
    }
    CFUUIDRef iunknown_uuid = CFUUIDGetConstantUUIDWithBytes(kCFAllocatorDefault, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46);
    Boolean matches = CFEqual(requested_uuid, kAudioServerPlugInDriverInterfaceUUID) || CFEqual(requested_uuid, iunknown_uuid);
    CFRelease(requested_uuid);
    if (matches) {
        driver_add_ref(driver);
        *out_interface = &g_interface;
        return S_OK;
    }
    return E_NOINTERFACE;
}

static OSStatus driver_initialize(AudioServerPlugInDriverRef driver, AudioServerPlugInHostRef host) {
    HearlyDriver *state = driver_state(driver);
    state->host = host;
    state->anchor_host_time = mach_absolute_time();
    state->sample_time = 0;
    state->seed = 1;
    if (host != NULL && host->PropertiesChanged != NULL) {
        AudioObjectPropertyAddress address = { kAudioPlugInPropertyDeviceList, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
        host->PropertiesChanged(host, HEARLY_PLUGIN_OBJECT, 1, &address);
    }
    return noErr;
}

static OSStatus driver_create_device(AudioServerPlugInDriverRef driver, CFDictionaryRef description, const AudioServerPlugInClientInfo *client_info, AudioObjectID *out_device) {
    (void)driver;
    (void)description;
    (void)client_info;
    (void)out_device;
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus driver_destroy_device(AudioServerPlugInDriverRef driver, AudioObjectID device_id) {
    (void)driver;
    (void)device_id;
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus driver_device_client(AudioServerPlugInDriverRef driver, AudioObjectID device_id, const AudioServerPlugInClientInfo *client_info) {
    (void)driver;
    (void)device_id;
    (void)client_info;
    return noErr;
}

static OSStatus driver_configuration_change(AudioServerPlugInDriverRef driver, AudioObjectID device_id, UInt64 action, void *change_info) {
    (void)driver;
    (void)device_id;
    (void)action;
    (void)change_info;
    return noErr;
}

static Boolean driver_has_property(AudioServerPlugInDriverRef driver, AudioObjectID object_id, pid_t client_pid, const AudioObjectPropertyAddress *address) {
    (void)driver;
    (void)client_pid;
    return has_property(object_id, address);
}

static OSStatus driver_is_property_settable(AudioServerPlugInDriverRef driver, AudioObjectID object_id, pid_t client_pid, const AudioObjectPropertyAddress *address, Boolean *out_settable) {
    (void)driver;
    (void)client_pid;
    if (out_settable == NULL || !has_property(object_id, address)) {
        return kAudioHardwareUnknownPropertyError;
    }
    *out_settable = false;
    return noErr;
}

static OSStatus driver_property_data_size(AudioServerPlugInDriverRef driver, AudioObjectID object_id, pid_t client_pid, const AudioObjectPropertyAddress *address, UInt32 qualifier_size, const void *qualifier, UInt32 *out_size) {
    (void)driver;
    (void)client_pid;
    (void)qualifier_size;
    (void)qualifier;
    if (out_size == NULL || !has_property(object_id, address)) {
        return kAudioHardwareUnknownPropertyError;
    }

    switch (address->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioDevicePropertyTransportType:
        case kAudioDevicePropertyDeviceIsAlive:
        case kAudioDevicePropertyDeviceIsRunning:
        case kAudioDevicePropertyBufferFrameSize:
        case kAudioDevicePropertyUsesVariableBufferFrameSizes:
        case kAudioDevicePropertyLatency:
        case kAudioDevicePropertySafetyOffset:
        case kAudioDevicePropertyZeroTimeStampPeriod:
        case kAudioDevicePropertyClockDomain:
        case kAudioDevicePropertyDeviceCanBeDefaultDevice:
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
        case kAudioStreamPropertyIsActive:
        case kAudioStreamPropertyDirection:
        case kAudioStreamPropertyTerminalType:
        case kAudioStreamPropertyStartingChannel:
            *out_size = sizeof(UInt32);
            return noErr;
        case kAudioObjectPropertyOwnedObjects:
            *out_size = object_id == HEARLY_PLUGIN_OBJECT ? sizeof(AudioObjectID) : object_id == HEARLY_DEVICE_OBJECT ? 2 * sizeof(AudioObjectID) : 0;
            return noErr;
        case kAudioDevicePropertyStreams:
            *out_size = address->mScope == kAudioObjectPropertyScopeGlobal ? 2 * sizeof(AudioObjectID) : sizeof(AudioObjectID);
            return noErr;
        case kAudioDevicePropertyPreferredChannelsForStereo:
            *out_size = 2 * sizeof(UInt32);
            return noErr;
        case kAudioPlugInPropertyDeviceList:
            *out_size = sizeof(AudioObjectID);
            return noErr;
        case kAudioDevicePropertyNominalSampleRate:
            *out_size = sizeof(Float64);
            return noErr;
        case kAudioDevicePropertyAvailableNominalSampleRates:
        case kAudioDevicePropertyBufferFrameSizeRange:
            *out_size = sizeof(AudioValueRange);
            return noErr;
        case kAudioDevicePropertyStreamConfiguration:
            *out_size = offsetof(AudioBufferList, mBuffers) + sizeof(AudioBuffer);
            return noErr;
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat:
            *out_size = sizeof(AudioStreamBasicDescription);
            return noErr;
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats:
            *out_size = sizeof(AudioStreamRangedDescription);
            return noErr;
        case kAudioPlugInPropertyTranslateUIDToDevice:
            *out_size = sizeof(AudioObjectID);
            return noErr;
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyModelName:
        case kAudioObjectPropertyManufacturer:
        case kAudioDevicePropertyDeviceUID:
        case kAudioDevicePropertyModelUID:
            *out_size = sizeof(CFStringRef);
            return noErr;
        default:
            return kAudioHardwareUnknownPropertyError;
    }
}

static AudioObjectID object_owner(AudioObjectID object_id) {
    switch (object_id) {
        case HEARLY_PLUGIN_OBJECT: return kAudioObjectSystemObject;
        case HEARLY_DEVICE_OBJECT: return HEARLY_PLUGIN_OBJECT;
        case HEARLY_STREAM_OBJECT: return HEARLY_DEVICE_OBJECT;
        case HEARLY_OUTPUT_STREAM_OBJECT: return HEARLY_DEVICE_OBJECT;
        default: return kAudioObjectUnknown;
    }
}

static AudioClassID object_class(AudioObjectID object_id) {
    switch (object_id) {
        case HEARLY_PLUGIN_OBJECT: return kAudioPlugInClassID;
        case HEARLY_DEVICE_OBJECT: return kAudioDeviceClassID;
        case HEARLY_STREAM_OBJECT: return kAudioStreamClassID;
        case HEARLY_OUTPUT_STREAM_OBJECT: return kAudioStreamClassID;
        default: return kAudioObjectClassID;
    }
}

static CFStringRef object_name(AudioObjectID object_id) {
    switch (object_id) {
        case HEARLY_DEVICE_OBJECT: return CFSTR("Hearly Microphone");
        case HEARLY_STREAM_OBJECT: return CFSTR("Hearly Input Stream");
        case HEARLY_OUTPUT_STREAM_OBJECT: return CFSTR("Hearly Processed Audio Output");
        default: return CFSTR("Hearly Audio");
    }
}

static OSStatus driver_get_property_data(AudioServerPlugInDriverRef driver, AudioObjectID object_id, pid_t client_pid, const AudioObjectPropertyAddress *address, UInt32 qualifier_size, const void *qualifier, UInt32 data_size, UInt32 *out_size, void *out_data) {
    HearlyDriver *state = driver_state(driver);
    (void)client_pid;
    (void)qualifier_size;
    if (out_data == NULL || !has_property(object_id, address)) {
        return kAudioHardwareUnknownPropertyError;
    }

    switch (address->mSelector) {
        case kAudioObjectPropertyBaseClass: {
            AudioClassID value = kAudioObjectClassID;
            return copy_value(&value, sizeof(value), data_size, out_size, out_data);
        }
        case kAudioObjectPropertyClass: {
            AudioClassID value = object_class(object_id);
            return copy_value(&value, sizeof(value), data_size, out_size, out_data);
        }
        case kAudioObjectPropertyOwner: {
            AudioObjectID value = object_owner(object_id);
            return copy_value(&value, sizeof(value), data_size, out_size, out_data);
        }
        case kAudioObjectPropertyOwnedObjects: {
            AudioObjectID values[] = { HEARLY_STREAM_OBJECT, HEARLY_OUTPUT_STREAM_OBJECT };
            if (object_id == HEARLY_PLUGIN_OBJECT) { values[0] = HEARLY_DEVICE_OBJECT; return copy_value(values, sizeof(AudioObjectID), data_size, out_size, out_data); }
            if (object_id == HEARLY_DEVICE_OBJECT) return copy_value(values, sizeof(values), data_size, out_size, out_data);
            if (out_size != NULL) *out_size = 0;
            return noErr;
        }
        case kAudioDevicePropertyStreams: {
            AudioObjectID values[] = { HEARLY_STREAM_OBJECT, HEARLY_OUTPUT_STREAM_OBJECT };
            if (address->mScope == kAudioObjectPropertyScopeGlobal) return copy_value(values, sizeof(values), data_size, out_size, out_data);
            AudioObjectID value = address->mScope == kAudioDevicePropertyScopeInput ? HEARLY_STREAM_OBJECT : HEARLY_OUTPUT_STREAM_OBJECT;
            return copy_value(&value, sizeof(value), data_size, out_size, out_data);
        }
        case kAudioDevicePropertyPreferredChannelsForStereo: {
            UInt32 values[] = { 1, 2 };
            return copy_value(values, sizeof(values), data_size, out_size, out_data);
        }
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyModelName:
            return copy_string(object_name(object_id), data_size, out_size, out_data);
        case kAudioObjectPropertyManufacturer:
            return copy_string(CFSTR("Hearly"), data_size, out_size, out_data);
        case kAudioPlugInPropertyDeviceList: {
            AudioObjectID value = HEARLY_DEVICE_OBJECT;
            return copy_value(&value, sizeof(value), data_size, out_size, out_data);
        }
        case kAudioPlugInPropertyTranslateUIDToDevice: {
            if (qualifier == NULL) return kAudioHardwareBadPropertySizeError;
            CFStringRef uid = *(CFStringRef *)qualifier;
            AudioObjectID value = (uid != NULL && CFEqual(uid, CFSTR("live.hearely.virtual-mic"))) ? HEARLY_DEVICE_OBJECT : kAudioObjectUnknown;
            return copy_value(&value, sizeof(value), data_size, out_size, out_data);
        }
        case kAudioDevicePropertyDeviceUID:
            return copy_string(CFSTR("live.hearely.virtual-mic"), data_size, out_size, out_data);
        case kAudioDevicePropertyModelUID:
            return copy_string(CFSTR("live.hearely.virtual-mic.model"), data_size, out_size, out_data);
        case kAudioDevicePropertyTransportType: {
            UInt32 value = kAudioDeviceTransportTypeVirtual;
            return copy_value(&value, sizeof(value), data_size, out_size, out_data);
        }
        case kAudioDevicePropertyDeviceIsAlive: {
            UInt32 value = 1;
            return copy_value(&value, sizeof(value), data_size, out_size, out_data);
        }
        case kAudioDevicePropertyDeviceIsRunning: {
            UInt32 value = state->running_clients > 0;
            return copy_value(&value, sizeof(value), data_size, out_size, out_data);
        }
        case kAudioDevicePropertyNominalSampleRate: {
            Float64 value = HEARLY_SAMPLE_RATE;
            return copy_value(&value, sizeof(value), data_size, out_size, out_data);
        }
        case kAudioDevicePropertyAvailableNominalSampleRates: {
            AudioValueRange value = { HEARLY_SAMPLE_RATE, HEARLY_SAMPLE_RATE };
            return copy_value(&value, sizeof(value), data_size, out_size, out_data);
        }
        case kAudioDevicePropertyBufferFrameSize: {
            UInt32 value = HEARLY_BUFFER_FRAMES;
            return copy_value(&value, sizeof(value), data_size, out_size, out_data);
        }
        case kAudioDevicePropertyBufferFrameSizeRange: {
            AudioValueRange value = { HEARLY_BUFFER_FRAMES, HEARLY_BUFFER_FRAMES };
            return copy_value(&value, sizeof(value), data_size, out_size, out_data);
        }
        case kAudioDevicePropertyUsesVariableBufferFrameSizes: {
            UInt32 value = 0;
            return copy_value(&value, sizeof(value), data_size, out_size, out_data);
        }
        case kAudioDevicePropertyLatency: {
            UInt32 value = address->mScope == kAudioDevicePropertyScopeInput ? HEARLY_LOOPBACK_DELAY : 0;
            return copy_value(&value, sizeof(value), data_size, out_size, out_data);
        }
        case kAudioDevicePropertySafetyOffset:
        case kAudioDevicePropertyClockDomain:
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice: {
            UInt32 value = 0;
            return copy_value(&value, sizeof(value), data_size, out_size, out_data);
        }
        case kAudioDevicePropertyZeroTimeStampPeriod: {
            UInt32 value = HEARLY_BUFFER_FRAMES;
            return copy_value(&value, sizeof(value), data_size, out_size, out_data);
        }
        case kAudioDevicePropertyDeviceCanBeDefaultDevice: {
            UInt32 value = address->mScope == kAudioDevicePropertyScopeInput;
            return copy_value(&value, sizeof(value), data_size, out_size, out_data);
        }
        case kAudioDevicePropertyStreamConfiguration: {
            AudioBufferList *buffer_list = (AudioBufferList *)out_data;
            if (data_size < offsetof(AudioBufferList, mBuffers) + sizeof(AudioBuffer)) return kAudioHardwareBadPropertySizeError;
            buffer_list->mNumberBuffers = 1;
            buffer_list->mBuffers[0].mNumberChannels = HEARLY_CHANNELS;
            buffer_list->mBuffers[0].mDataByteSize = 0;
            buffer_list->mBuffers[0].mData = NULL;
            if (out_size != NULL) *out_size = offsetof(AudioBufferList, mBuffers) + sizeof(AudioBuffer);
            return noErr;
        }
        case kAudioStreamPropertyIsActive: {
            UInt32 value = 1;
            return copy_value(&value, sizeof(value), data_size, out_size, out_data);
        }
        case kAudioStreamPropertyDirection: {
            UInt32 value = object_id == HEARLY_STREAM_OBJECT ? 1 : 0;
            return copy_value(&value, sizeof(value), data_size, out_size, out_data);
        }
        case kAudioStreamPropertyTerminalType: {
            UInt32 value = object_id == HEARLY_STREAM_OBJECT ? kAudioStreamTerminalTypeMicrophone : kAudioStreamTerminalTypeSpeaker;
            return copy_value(&value, sizeof(value), data_size, out_size, out_data);
        }
        case kAudioStreamPropertyStartingChannel: {
            UInt32 value = 1;
            return copy_value(&value, sizeof(value), data_size, out_size, out_data);
        }
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat: {
            AudioStreamBasicDescription value = stream_format();
            return copy_value(&value, sizeof(value), data_size, out_size, out_data);
        }
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats: {
            AudioStreamRangedDescription value;
            memset(&value, 0, sizeof(value));
            value.mFormat = stream_format();
            value.mSampleRateRange.mMinimum = HEARLY_SAMPLE_RATE;
            value.mSampleRateRange.mMaximum = HEARLY_SAMPLE_RATE;
            return copy_value(&value, sizeof(value), data_size, out_size, out_data);
        }
        default:
            return kAudioHardwareUnknownPropertyError;
    }
}

static OSStatus driver_set_property_data(AudioServerPlugInDriverRef driver, AudioObjectID object_id, pid_t client_pid, const AudioObjectPropertyAddress *address, UInt32 qualifier_size, const void *qualifier, UInt32 data_size, const void *data) {
    (void)driver;
    (void)object_id;
    (void)client_pid;
    (void)address;
    (void)qualifier_size;
    (void)qualifier;
    (void)data_size;
    (void)data;
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus driver_start_io(AudioServerPlugInDriverRef driver, AudioObjectID device_id, UInt32 client_id) {
    (void)device_id;
    (void)client_id;
    HearlyDriver *state = driver_state(driver);
    state->running_clients += 1;
    return noErr;
}

static OSStatus driver_stop_io(AudioServerPlugInDriverRef driver, AudioObjectID device_id, UInt32 client_id) {
    (void)device_id;
    (void)client_id;
    HearlyDriver *state = driver_state(driver);
    if (state->running_clients > 0) state->running_clients -= 1;
    return noErr;
}

static OSStatus driver_zero_timestamp(AudioServerPlugInDriverRef driver, AudioObjectID device_id, UInt32 client_id, Float64 *sample_time, UInt64 *host_time, UInt64 *seed) {
    (void)device_id;
    (void)client_id;
    HearlyDriver *state = driver_state(driver);
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    UInt64 now = mach_absolute_time();
    Float64 ticks_per_frame = 1000000000.0 * timebase.denom / timebase.numer / HEARLY_SAMPLE_RATE;
    UInt64 periods = (UInt64)((now - state->anchor_host_time) / (ticks_per_frame * HEARLY_BUFFER_FRAMES));
    Float64 frames = (Float64)(periods * HEARLY_BUFFER_FRAMES);
    if (sample_time != NULL) *sample_time = frames;
    if (host_time != NULL) *host_time = state->anchor_host_time + (UInt64)(frames * ticks_per_frame);
    if (seed != NULL) *seed = state->seed;
    return noErr;
}

static OSStatus driver_will_do_io(AudioServerPlugInDriverRef driver, AudioObjectID device_id, UInt32 client_id, UInt32 operation_id, Boolean *will_do, Boolean *will_do_in_place) {
    (void)driver;
    (void)device_id;
    (void)client_id;
    if (will_do == NULL || will_do_in_place == NULL) return kAudioHardwareIllegalOperationError;
    *will_do = operation_id == kAudioServerPlugInIOOperationReadInput || operation_id == kAudioServerPlugInIOOperationWriteMix;
    *will_do_in_place = *will_do;
    return noErr;
}

static OSStatus driver_begin_io(AudioServerPlugInDriverRef driver, AudioObjectID device_id, UInt32 client_id, UInt32 operation_id, UInt32 frame_count, const AudioServerPlugInIOCycleInfo *cycle_info) {
    (void)driver;
    (void)device_id;
    (void)client_id;
    (void)operation_id;
    (void)frame_count;
    (void)cycle_info;
    return noErr;
}

static OSStatus driver_do_io(AudioServerPlugInDriverRef driver, AudioObjectID device_id, AudioObjectID stream_id, UInt32 client_id, UInt32 operation_id, UInt32 frame_count, const AudioServerPlugInIOCycleInfo *cycle_info, void *main_buffer, void *secondary_buffer) {
    (void)device_id;
    (void)stream_id;
    (void)client_id;
    (void)cycle_info;
    (void)secondary_buffer;
    if (main_buffer == NULL || cycle_info == NULL) return noErr;
    HearlyDriver *state = driver_state(driver);
    // AudioServerPlugIn passes raw stream PCM, not an AudioBufferList.
    if (operation_id == kAudioServerPlugInIOOperationWriteMix && stream_id == HEARLY_OUTPUT_STREAM_OBJECT) {
        if (cycle_info->mOutputTime.mSampleTime >= 0) hearly_loopback_write(&state->loopback, (UInt64)cycle_info->mOutputTime.mSampleTime, (const Float32 *)main_buffer, frame_count);
    } else if (operation_id == kAudioServerPlugInIOOperationReadInput && stream_id == HEARLY_STREAM_OBJECT) {
        hearly_loopback_read(&state->loopback, (int64_t)cycle_info->mInputTime.mSampleTime - HEARLY_LOOPBACK_DELAY, (Float32 *)main_buffer, frame_count);
    }
    return noErr;
}

static OSStatus driver_end_io(AudioServerPlugInDriverRef driver, AudioObjectID device_id, UInt32 client_id, UInt32 operation_id, UInt32 frame_count, const AudioServerPlugInIOCycleInfo *cycle_info) {
    (void)driver;
    (void)device_id;
    (void)client_id;
    (void)operation_id;
    (void)frame_count;
    (void)cycle_info;
    return noErr;
}

void *HearlyAudioDriverFactory(CFAllocatorRef allocator, CFUUIDRef type_uuid) {
    (void)allocator;
    if (!CFEqual(type_uuid, kAudioServerPlugInTypeUUID)) return NULL;
    memset(&g_driver, 0, sizeof(g_driver));
    g_driver.interface.QueryInterface = driver_query_interface;
    g_driver.interface.AddRef = driver_add_ref;
    g_driver.interface.Release = driver_release;
    g_driver.interface.Initialize = driver_initialize;
    g_driver.interface.CreateDevice = driver_create_device;
    g_driver.interface.DestroyDevice = driver_destroy_device;
    g_driver.interface.AddDeviceClient = driver_device_client;
    g_driver.interface.RemoveDeviceClient = driver_device_client;
    g_driver.interface.PerformDeviceConfigurationChange = driver_configuration_change;
    g_driver.interface.AbortDeviceConfigurationChange = driver_configuration_change;
    g_driver.interface.HasProperty = driver_has_property;
    g_driver.interface.IsPropertySettable = driver_is_property_settable;
    g_driver.interface.GetPropertyDataSize = driver_property_data_size;
    g_driver.interface.GetPropertyData = driver_get_property_data;
    g_driver.interface.SetPropertyData = driver_set_property_data;
    g_driver.interface.StartIO = driver_start_io;
    g_driver.interface.StopIO = driver_stop_io;
    g_driver.interface.GetZeroTimeStamp = driver_zero_timestamp;
    g_driver.interface.WillDoIOOperation = driver_will_do_io;
    g_driver.interface.BeginIOOperation = driver_begin_io;
    g_driver.interface.DoIOOperation = driver_do_io;
    g_driver.interface.EndIOOperation = driver_end_io;
    g_driver.reference_count = 1;
    g_interface = &g_driver.interface;
    return &g_interface;
}
