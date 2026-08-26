#ifndef _LINUX_KERNELSU_H
#define _LINUX_KERNELSU_H

#include <linux/fs.h>
#include <linux/types.h>
#include <linux/uidgid.h>

struct filename;
struct stat;
struct stat64;

#ifdef CONFIG_KSU
int ksu_handle_execveat(int *fd, struct filename **filename_ptr,
                        void *argv, void *envp, int *flags);
int ksu_handle_faccessat(int *dfd, const char __user **filename_user,
                        int *mode, int *flags);
int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);
int ksu_handle_vfs_read(struct file **file_ptr, char __user **buf_ptr,
                        size_t *count_ptr, loff_t **pos);
void ksu_handle_newfstat_ret(unsigned int *fd,
                             struct stat __user **statbuf);
void ksu_handle_fstat64_ret(unsigned long *fd,
                            struct stat64 __user **statbuf);
int ksu_handle_setresuid(uid_t ruid, uid_t euid, uid_t suid);
int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd,
                          void __user **arg);
int ksu_handle_input_handle_event(unsigned int *type, unsigned int *code,
                                  int *value);
#else
static inline int ksu_handle_execveat(int *fd, struct filename **filename_ptr,
                                      void *argv, void *envp, int *flags)
{
    return 0;
}
static inline int ksu_handle_faccessat(int *dfd,
                                       const char __user **filename_user,
                                       int *mode, int *flags)
{
    return 0;
}
static inline int ksu_handle_stat(int *dfd,
                                  const char __user **filename_user,
                                  int *flags)
{
    return 0;
}
static inline int ksu_handle_vfs_read(struct file **file_ptr,
                                      char __user **buf_ptr,
                                      size_t *count_ptr, loff_t **pos)
{
    return 0;
}
static inline void ksu_handle_newfstat_ret(unsigned int *fd,
                                           struct stat __user **statbuf)
{
}
static inline void ksu_handle_fstat64_ret(unsigned long *fd,
                                          struct stat64 __user **statbuf)
{
}
static inline int ksu_handle_setresuid(uid_t ruid, uid_t euid, uid_t suid)
{
    return 0;
}
static inline int ksu_handle_sys_reboot(int magic1, int magic2,
                                        unsigned int cmd, void __user **arg)
{
    return 0;
}
static inline int ksu_handle_input_handle_event(unsigned int *type,
                                                unsigned int *code,
                                                int *value)
{
    return 0;
}
#endif

#endif /* _LINUX_KERNELSU_H */
