#include "CProcessSupport.h"
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <pthread.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

// pipe()+fcntl() is not atomic on macOS. Serialize our own spawns so another
// collector task cannot inherit a writer during that short CLOEXEC window.
static pthread_mutex_t spawn_lock = PTHREAD_MUTEX_INITIALIZER;

static void close_pair(int descriptors[2]) {
    for (int i = 0; i < 2; i++) if (descriptors[i] >= 0) close(descriptors[i]);
}

static int make_pipe(int descriptors[2]) {
    if (pipe(descriptors) < 0) return errno;
    for (int i = 0; i < 2; i++) {
        if (descriptors[i] <= STDERR_FILENO) {
            int replacement = fcntl(descriptors[i], F_DUPFD_CLOEXEC, STDERR_FILENO + 1);
            if (replacement < 0) return errno;
            close(descriptors[i]); descriptors[i] = replacement;
        }
        // CLOEXEC protects other simultaneous subprocess launches from holding pipes open.
        if (fcntl(descriptors[i], F_SETFD, FD_CLOEXEC) < 0) return errno;
    }
    if (fcntl(descriptors[0], F_SETFL, O_NONBLOCK) < 0) return errno;
    return 0;
}

int ssp_spawn(const char *path, char *const argv[], char *const envp[], ssp_child *child) {
    pthread_mutex_lock(&spawn_lock);
    int output[2] = {-1, -1}, error[2] = {-1, -1};
    int result = make_pipe(output);
    if (result) goto cleanup;
    result = make_pipe(error);
    if (result) goto cleanup;
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    result = posix_spawn_file_actions_init(&actions);
    if (result) goto cleanup;
    result = posix_spawnattr_init(&attributes);
    if (result) { posix_spawn_file_actions_destroy(&actions); goto cleanup; }

#define CHECK(call) do { result = (call); if (result) goto destroy; } while (0)
    CHECK(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0));
    CHECK(posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO));
    CHECK(posix_spawn_file_actions_adddup2(&actions, error[1], STDERR_FILENO));
    CHECK(posix_spawn_file_actions_addclose(&actions, output[0]));
    CHECK(posix_spawn_file_actions_addclose(&actions, output[1]));
    CHECK(posix_spawn_file_actions_addclose(&actions, error[0]));
    CHECK(posix_spawn_file_actions_addclose(&actions, error[1]));
    sigset_t empty, defaults;
    sigemptyset(&empty);
    sigemptyset(&defaults);
    sigaddset(&defaults, SIGPIPE);
    sigaddset(&defaults, SIGTERM);
    sigaddset(&defaults, SIGINT);
    sigaddset(&defaults, SIGHUP);
    CHECK(posix_spawnattr_setsigmask(&attributes, &empty));
    CHECK(posix_spawnattr_setsigdefault(&attributes, &defaults));
    CHECK(posix_spawnattr_setpgroup(&attributes, 0));
    short flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF;
#ifdef POSIX_SPAWN_CLOEXEC_DEFAULT
    flags |= POSIX_SPAWN_CLOEXEC_DEFAULT;
#endif
    CHECK(posix_spawnattr_setflags(&attributes, flags));
    result = posix_spawn(&child->pid, path, &actions, &attributes, argv, envp);
destroy:
    posix_spawnattr_destroy(&attributes);
    posix_spawn_file_actions_destroy(&actions);
    if (!result) {
        close(output[1]); close(error[1]);
        child->output_fd = output[0]; child->error_fd = error[0];
        pthread_mutex_unlock(&spawn_lock);
        return 0;
    }
cleanup:
    close_pair(output); close_pair(error);
    pthread_mutex_unlock(&spawn_lock);
    return result;
#undef CHECK
}

int ssp_has_exited(pid_t pid) {
    siginfo_t info;
    memset(&info, 0, sizeof(info));
    if (waitid(P_PID, (id_t)pid, &info, WEXITED | WNOHANG | WNOWAIT) < 0)
        return errno == EINTR ? 0 : -errno;
    return info.si_pid == pid;
}

int ssp_signal_group(pid_t pid, int signal_number) {
    if (pid <= 0) return EINVAL;
    if (kill(-pid, signal_number) < 0) return errno;
    return 0;
}

int ssp_reap(pid_t pid, int *exit_code, int *signal_number) {
    int status;
    pid_t result;
    do { result = waitpid(pid, &status, 0); } while (result < 0 && errno == EINTR);
    if (result < 0) return errno;
    *exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    *signal_number = WIFSIGNALED(status) ? WTERMSIG(status) : 0;
    return 0;
}
