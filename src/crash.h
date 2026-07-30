/*
 * Fault reporting for the loaded module.
 *
 * A crash inside libicerage.so is invisible from the outside: the process
 * has no debugger, the .so is not on disk, and qemu only reports the faulting
 * address. Naming the faulting instruction's offset inside the module is what
 * turns "segfault at 0x4" into something objdump can answer.
 */
#ifndef ICERAGE_CRASH_H
#define ICERAGE_CRASH_H

#include "so_util.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Installs the handler and remembers where the module was mapped. */
void crash_report_init(so_module *mod, const char *soname);

#ifdef __cplusplus
}
#endif

#endif /* ICERAGE_CRASH_H */
