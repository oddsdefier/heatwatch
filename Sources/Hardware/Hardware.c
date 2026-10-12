#include "Hardware.h"
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <libproc.h>
#include <sys/resource.h>
#include <mach/mach_time.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

/* AppleSMC read-only protocol. No write command exists in this module. */
typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } Version;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, memory; } Limits;
typedef struct { uint32_t size, type; uint8_t attributes; } KeyInfo;
typedef struct {
    uint32_t key; Version version; Limits limits; KeyInfo info;
    uint8_t result, status, command; uint32_t index; uint8_t bytes[32];
} Message;
_Static_assert(sizeof(Message) == 80, "Invalid SMC protocol layout");
struct HWConnection { io_connect_t port; };

static uint32_t fourcc(const char *s) {
    return ((uint32_t)(uint8_t)s[0] << 24) | ((uint32_t)(uint8_t)s[1] << 16)
        | ((uint32_t)(uint8_t)s[2] << 8) | (uint8_t)s[3];
}
static int call(HWConnection *c, const Message *in, Message *out) {
    size_t size = sizeof(*out);
    memset(out, 0, size);
    return IOConnectCallStructMethod(c->port, 2, in, sizeof(*in), out, &size) == KERN_SUCCESS
        && size == sizeof(*out) && out->result == 0;
}
HWConnection *hw_open(void) {
    io_iterator_t iterator = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &iterator) != KERN_SUCCESS)
        return NULL;
    io_service_t service;
    io_connect_t port = 0;
    while ((service = IOIteratorNext(iterator))) {
        io_name_t name = {0};
        if (IORegistryEntryGetName(service, name) == KERN_SUCCESS
            && (strcmp(name, "AppleSMCKeysEndpoint") == 0 || strcmp(name, "AppleSMC") == 0))
            IOServiceOpen(service, mach_task_self(), 0, &port);
        IOObjectRelease(service);
        if (port) break;
    }
    IOObjectRelease(iterator);
    if (!port) return NULL;
    HWConnection *c = calloc(1, sizeof(*c));
    if (!c) { IOServiceClose(port); return NULL; }
    c->port = port;
    return c;
}
void hw_close(HWConnection *c) {
    if (c) { IOServiceClose(c->port); free(c); }
}
double hw_sensor(HWConnection *c, const char *key) {
    if (!c || !key || strlen(key) != 4) return NAN;
    Message in = {.key = fourcc(key), .command = 9}, out;
    if (!call(c, &in, &out)) return NAN;
    KeyInfo info = out.info;
    if (info.size > 32 || info.size == 0) return NAN;
    in.info = info;
    in.command = 5;
    if (!call(c, &in, &out)) return NAN;
    if (info.type == fourcc("flt ") && info.size == 4) {
        float value;
        memcpy(&value, out.bytes, sizeof(value));
        return isfinite(value) ? value : NAN;
    }
    if (info.type == fourcc("sp78") && info.size == 2)
        return (int16_t)(((uint16_t)out.bytes[0] << 8) | out.bytes[1]) / 256.0;
    if (info.type == fourcc("fpe2") && info.size == 2)
        return (((uint16_t)out.bytes[0] << 8) | out.bytes[1]) / 4.0;
    return NAN;
}
int hw_charging(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"));
    if (!service) return -1;
    CFTypeRef value = IORegistryEntryCreateCFProperty(service, CFSTR("IsCharging"), kCFAllocatorDefault, 0);
    IOObjectRelease(service);
    if (!value) return -1;
    int result = -1;
    if (CFGetTypeID(value) == CFBooleanGetTypeID()) result = CFBooleanGetValue(value) ? 1 : 0;
    else if (CFGetTypeID(value) == CFNumberGetTypeID()) CFNumberGetValue(value, kCFNumberIntType, &result);
    CFRelease(value);
    return result;
}
double hw_gpu_usage(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"));
    if (!service) return NAN;
    CFTypeRef stats = IORegistryEntryCreateCFProperty(service, CFSTR("PerformanceStatistics"), kCFAllocatorDefault, 0);
    IOObjectRelease(service);
    double usage = NAN;
    if (stats && CFGetTypeID(stats) == CFDictionaryGetTypeID()) {
        CFTypeRef value = CFDictionaryGetValue(stats, CFSTR("Device Utilization %"));
        if (value && CFGetTypeID(value) == CFNumberGetTypeID()) CFNumberGetValue(value, kCFNumberDoubleType, &usage);
    }
    if (stats) CFRelease(stats);
    return isfinite(usage) && usage >= 0 && usage <= 100 ? usage : NAN;
}
int hw_processes(HWProcess **output) {
    *output = NULL;
    mach_timebase_info_data_t timebase;
    if (mach_timebase_info(&timebase) != KERN_SUCCESS || timebase.denom == 0) return -1;
    int estimate = proc_listallpids(NULL, 0);
    if (estimate <= 0) return -1;
    int capacity = estimate + 256;
    pid_t *pids = calloc((size_t)capacity, sizeof(pid_t));
    if (!pids) return -1;
    int count = proc_listallpids(pids, capacity * (int)sizeof(pid_t));
    if (count <= 0 || count >= capacity) { free(pids); return -1; }
    HWProcess *items = calloc((size_t)count, sizeof(*items));
    if (!items) { free(pids); return -1; }
    int used = 0;
    for (int i = 0; i < count; i++) {
        if (pids[i] <= 0) continue;
        struct rusage_info_v2 usage = {0};
        if (proc_pid_rusage(pids[i], RUSAGE_INFO_V2, (rusage_info_t *)&usage) != 0) continue;
        HWProcess *item = &items[used++];
        item->pid = pids[i];
        item->birth = (uint64_t)((__uint128_t)usage.ri_proc_start_abstime * timebase.numer / timebase.denom);
        /* rusage CPU counters use Mach ticks, not nanoseconds, on Apple Silicon. */
        item->cpu_ns = (uint64_t)(((__uint128_t)usage.ri_user_time + usage.ri_system_time)
                                 * timebase.numer / timebase.denom);
        hw_process_path(item);
    }
    free(pids);
    *output = items;
    return used;
}
void hw_process_path(HWProcess *item) {
    memset(item->path, 0, sizeof(item->path));
    if (proc_pidpath(item->pid, item->path, sizeof(item->path)) <= 0)
        item->path[0] = 0;
    item->path[sizeof(item->path) - 1] = 0;
}
void hw_free_processes(HWProcess *items) { free(items); }
