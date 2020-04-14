#include <asm/syscall.h>
#include <linux/in.h>
#include <linux/in6.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/net.h>
#include <linux/proc_fs.h>
#include <linux/sched.h>
#include <linux/socket.h>
#include <linux/string.h>
#include <linux/syscalls.h>
#include <linux/time.h>
#include <linux/timekeeping32.h>
#include <linux/types.h>
#include <linux/uaccess.h>

MODULE_LICENSE("APACHE2");
MODULE_AUTHOR("Rodrigo Alves Lima");
MODULE_DESCRIPTION("Specialize recvfrom syscall.");
MODULE_VERSION("0.1");

#define RECVFROM_BUFF_SIZE 524288
#define MAX_RECVFROM_LOG_ENTRY_LEN 512

typedef struct recvfrom_buff_entry {
  long long ts;               /* Timestamp */
  int ret;                    /* Return value */
  int pid;                    /* Process ID */
  int tid;                    /* Thread ID */
  int sock_fd;                /* Socket file descriptor */
} t_recvfrom_buff_entry;
static t_recvfrom_buff_entry recvfrom_buff[RECVFROM_BUFF_SIZE];
static atomic_t recvfrom_buff_count;

int recvfrom_proc_read(struct file *proc, char __user *buff, unsigned long len,
    long long *offset) {
  char log_entry[MAX_RECVFROM_LOG_ENTRY_LEN];
  int log_entry_len;
  int copied_len = 0;
  t_recvfrom_buff_entry *buff_entry;

  if (*offset == 0) {
    log_entry_len = sprintf(log_entry, "RET,TS,PID,TID,SOCK_FD\n");
    copy_to_user(buff + copied_len, log_entry, log_entry_len);
    copied_len += log_entry_len;
  }
  while (*offset < RECVFROM_BUFF_SIZE && *offset < atomic_read(&recvfrom_buff_count)) {
    buff_entry = &recvfrom_buff[*offset];
    log_entry_len = sprintf(log_entry, "%d,%lld,%d,%d,%d\n",
        buff_entry->ret, buff_entry->ts, buff_entry->pid, buff_entry->tid,
        buff_entry->sock_fd);
    if (copied_len + log_entry_len >= len)
      break;
    copy_to_user(buff + copied_len, log_entry, log_entry_len);
    copied_len += log_entry_len;
    *offset += 1;
  }
  return copied_len;
}

asmlinkage long (*original_recvfrom)(int, void __user *, unsigned long,
    unsigned int, struct sockaddr __user *, int __user *);

asmlinkage long specialized_recvfrom(int fd, void __user *ubuf,
    unsigned long size, unsigned int flags, struct sockaddr __user *addr,
    int __user *addr_len) {
  int buff_entry_idx;
  struct timeval ts;
  t_recvfrom_buff_entry *buff_entry = NULL;

  buff_entry_idx = atomic_add_return(1, &recvfrom_buff_count) - 1;
  if (buff_entry_idx < RECVFROM_BUFF_SIZE) {
    do_gettimeofday(&ts);
    buff_entry = &recvfrom_buff[buff_entry_idx];
    buff_entry->ts = ts.tv_sec * 1000000LL + ts.tv_usec;
    buff_entry->pid = task_tgid_nr(current);
    buff_entry->tid = task_pid_nr(current);
    buff_entry->sock_fd = fd;
    return (buff_entry->ret =
        original_recvfrom(fd, ubuf, size, flags, addr, addr_len));
  }
  return original_recvfrom(fd, ubuf, size, flags, addr, addr_len);
}

static const struct file_operations recvfrom_proc_ops = {
  .read = (void *) recvfrom_proc_read
};
static struct proc_dir_entry *recvfrom_proc_dir_entry;

static int __init specialize_recvfrom(void) {
  atomic_set(&recvfrom_buff_count, 0);
  recvfrom_proc_dir_entry = proc_create("spec_recvfrom", 0, NULL,
      &recvfrom_proc_ops);
  original_recvfrom = (void *) sys_call_table[__NR_recvfrom];
  sys_call_table[__NR_recvfrom] = (void *) &specialized_recvfrom;

  printk(KERN_INFO "Specialized recvfrom syscall.\n");

  return 0;
}

static void __exit restore_recvfrom(void) {
  sys_call_table[__NR_recvfrom] = (void *) original_recvfrom;
  proc_remove(recvfrom_proc_dir_entry);

  printk(KERN_INFO "Restored recvfrom syscall.\n");
}

module_init(specialize_recvfrom);
module_exit(restore_recvfrom);
