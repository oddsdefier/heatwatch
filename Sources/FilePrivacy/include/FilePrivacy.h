#ifndef HEATWATCH_FILE_PRIVACY_H
#define HEATWATCH_FILE_PRIVACY_H
/* Remove macOS extended ACL entries from a held, owned file descriptor. */
int privacy_clear_acl(int fd);
#endif
