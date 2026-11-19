/* Publish an already validated Git generation on the same filesystem.
 * rename(2) can replace a symlink, but cannot replace a populated directory.
 * Exchange the two entries atomically in that case, or leave current intact.
 */
#define _GNU_SOURCE
#define _DARWIN_C_SOURCE
#include <errno.h>
#include <stdio.h>
#ifdef __linux__
#include <fcntl.h>
#include <sys/syscall.h>
#include <unistd.h>
#endif

int main(int argc, char **argv)
{
    if (argc != 3)
        return 2;
    if (rename(argv[1], argv[2]) == 0)
        return 0;
    if (errno == ENOTEMPTY || errno == EEXIST || errno == ENOTDIR || errno == EISDIR) {
#if defined(__linux__) && defined(SYS_renameat2)
        /* Old libc headers may omit RENAME_EXCHANGE even on supported kernels. */
        if (syscall(SYS_renameat2, AT_FDCWD, argv[1], AT_FDCWD, argv[2], 2U) == 0)
            return 0;
#elif defined(__APPLE__) && defined(RENAME_SWAP)
        if (renamex_np(argv[1], argv[2], RENAME_SWAP) == 0)
            return 0;
#endif
    }
    perror("atomic Git activation");
    return 1;
}
