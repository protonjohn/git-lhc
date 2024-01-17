//
//  LHCInternalC.h
//
//  Tiny wrappers for macros that otherwise aren't accessible from Swift.
//
//  Created by John Biggs on 18.12.23.
//

#ifndef LHCInternalC_h
#define LHCInternalC_h

#include <sys/ioctl.h>
#include <stdbool.h>

// MARK: - Waitpid
bool child_terminated_from_signal(int);
bool child_was_stopped(int);
bool child_exited(int);
bool child_core_dumped(int);

int child_exit_status(int);
int child_termination_signal(int);
int child_stop_signal(int);

static int ioctl_fionread = FIONREAD;

#endif /* LHCInternalC_h */
