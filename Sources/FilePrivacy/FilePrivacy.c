#include "FilePrivacy.h"
#include <sys/types.h>
#include <sys/acl.h>
#include <errno.h>
#include <stddef.h>

int privacy_clear_acl(int fd) {
    acl_t empty = acl_init(0);
    if (!empty) return -1;
    int result = acl_set_fd_np(fd, empty, ACL_TYPE_EXTENDED);
    acl_free(empty);
    if (result != 0) return -1;
    errno = 0;
    acl_t actual = acl_get_fd_np(fd, ACL_TYPE_EXTENDED);
    /* macOS returns ENOENT for an absent ACL on a valid held descriptor. */
    if (!actual) return errno == ENOENT ? 0 : -1;
    acl_entry_t entry = NULL;
    errno = 0;
    result = acl_get_entry(actual, ACL_FIRST_ENTRY, &entry);
    int saved_errno = errno;
    acl_free(actual);
    return result == -1 && saved_errno == EINVAL ? 0 : -1;
}
