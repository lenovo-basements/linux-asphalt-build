/* macOS uses gen_init_cpio's existing read/write fallback. */
#include <errno.h>
#include <sys/types.h>
#define O_LARGEFILE 0
static inline ssize_t tb320fc_copy_file_range(int in_fd, off_t *in_offset,
                                            int out_fd, off_t *out_offset,
                                            size_t length, unsigned int flags)
{
    (void)in_fd; (void)in_offset; (void)out_fd; (void)out_offset;
    (void)length; (void)flags;
    errno = ENOSYS;
    return -1;
}
#define copy_file_range tb320fc_copy_file_range
