#ifndef HEATWATCH_HARDWARE_H
#define HEATWATCH_HARDWARE_H
#include <stdint.h>
#include <stddef.h>

typedef struct HWConnection HWConnection;
HWConnection *hw_open(void);
void hw_close(HWConnection *connection);
/* NAN means unavailable. These calls never change hardware settings. */
double hw_sensor(HWConnection *connection, const char *key);
int hw_charging(void); /* -1 unavailable, 0 no, 1 yes */
double hw_gpu_usage(void); /* NAN when the driver exposes no counter */

typedef struct {
    int32_t pid;
    uint64_t birth;
    uint64_t cpu_ns;
    char name[128];
    char path[1024];
} HWProcess;
/* Caller frees the returned array with hw_free_processes. */
int hw_processes(HWProcess **output);
void hw_process_path(HWProcess *process);
void hw_free_processes(HWProcess *processes);
#endif
