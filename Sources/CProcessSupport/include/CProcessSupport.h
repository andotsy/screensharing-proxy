#ifndef SSP_PROCESS_SUPPORT_H
#define SSP_PROCESS_SUPPORT_H
#include <sys/types.h>

typedef struct {
    pid_t pid;
    int output_fd;
    int error_fd;
    int input_fd;
} ssp_child;

// Returns errno (not -1). Each child owns a new process group. stdin is /dev/null.
int ssp_spawn(const char *path, char *const argv[], char *const envp[], ssp_child *child);
// Like ssp_spawn, but exposes a parent-owned stdin writer for a live adapter.
// Closing it informs the child of parent shutdown; the child must watch EOF.
int ssp_spawn_interactive(const char *path, char *const argv[], char *const envp[], ssp_child *child);
// Observe without reaping: the zombie reserves its PID until group cleanup.
// Returns 1 when exited, 0 while running, or -errno.
int ssp_has_exited(pid_t pid);
int ssp_signal_group(pid_t pid, int signal_number);
int ssp_reap(pid_t pid, int *exit_code, int *signal_number);
#endif
