//
//  LHCInternalC.c
//
//  Created by John Biggs on 18.12.23.
//

#include <sys/wait.h>
#include <stdbool.h>

// MARK: - Waitpid

__attribute__((always_inline)) int child_exit_status(int stat_loc) {
    return WEXITSTATUS(stat_loc);
}

__attribute__((always_inline)) bool child_terminated_from_signal(int stat_loc) {
    return WIFSIGNALED(stat_loc);
}

__attribute__((always_inline)) bool child_was_stopped(int stat_loc) {
    return WIFSTOPPED(stat_loc);
}

__attribute__((always_inline)) bool child_exited(int stat_loc) {
    return WIFEXITED(stat_loc);
}

__attribute__((always_inline)) int child_termination_signal(int stat_loc) {
    return WTERMSIG(stat_loc);
}

__attribute__((always_inline)) int child_stop_signal(int stat_loc) {
    return WSTOPSIG(stat_loc);
}

__attribute__((always_inline)) bool child_core_dumped(int stat_loc) {
    return WCOREDUMP(stat_loc);
}
