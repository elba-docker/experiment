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
MODULE_DESCRIPTION("Specialize sendto syscall.");
MODULE_VERSION("0.1");

#define SENDTO_BUFF_SIZE 524288
#define MAX_SENDTO_LOG_ENTRY_LEN 512

typedef struct sendto_buff_entry {
  long long ts;               /* Timestamp */
  int ret;                    /* Return value */
  int pid;                    /* Process ID */
  int tid;                    /* Thread ID */
  int sock_fd;                /* Socket file descriptor */
} t_sendto_buff_entry;
static t_sendto_buff_entry sendto_buff[SENDTO_BUFF_SIZE];
static atomic_t sendto_buff_count;

int sendto_proc_read(struct file *proc, char __user *buff, unsigned long len,
    long long *offset) {
  char log_entry[MAX_SENDTO_LOG_ENTRY_LEN];
  int log_entry_len;
  int copied_len = 0;
  t_sendto_buff_entry *buff_entry;

  if (*offset == 0) {
    log_entry_len = sprintf(log_entry, "RET,TS,PID,TID,SOCK_FD\n");
    copy_to_user(buff + copied_len, log_entry, log_entry_len);
    copied_len += log_entry_len;
  }
  while (*offset < SENDTO_BUFF_SIZE && *offset < atomic_read(&sendto_buff_count)) {
    buff_entry = &sendto_buff[*offset];
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

asmlinkage long (*original_sendto)(int, void __user *, unsigned long,
    unsigned int, struct sockaddr __user *, int);

asmlinkage long specialized_sendto(int fd, void __user *buff,
    unsigned long len, unsigned int flags, struct sockaddr __user *addr,
    int addr_len) {
  int buff_entry_idx;
  struct timeval ts;
  t_sendto_buff_entry *buff_entry = NULL;

  buff_entry_idx = atomic_add_return(1, &sendto_buff_count) - 1;
  if (buff_entry_idx < SENDTO_BUFF_SIZE) {
    do_gettimeofday(&ts);
    buff_entry = &sendto_buff[buff_entry_idx];
    buff_entry->ts = ts.tv_sec * 1000000LL + ts.tv_usec;
    buff_entry->pid = task_tgid_nr(current);
    buff_entry->tid = task_pid_nr(current);
    buff_entry->sock_fd = fd;
    return (buff_entry->ret =
        original_sendto(fd, buff, len, flags, addr, addr_len));
  }
  return original_sendto(fd, buff, len, flags, addr, addr_len);
}

static const struct file_operations sendto_proc_ops = {
  .read = (void *) sendto_proc_read
};
static struct proc_dir_entry *sendto_proc_dir_entry;

static int __init specialize_sendto(void) {
  atomic_set(&sendto_buff_count, 0);
  sendto_proc_dir_entry = proc_create("spec_sendto", 0, NULL,
      &sendto_proc_ops);
  original_sendto = (void *) sys_call_table[__NR_sendto];
  sys_call_table[__NR_sendto] = (void *) &specialized_sendto;

  printk(KERN_INFO "Specialized sendto syscalls.\n");

  return 0;
}

static void __exit restore_sendto(void) {
  sys_call_table[__NR_sendto] = (void *) original_sendto;
  proc_remove(sendto_proc_dir_entry);

  printk(KERN_INFO "Restored sendto syscall.\n");
}

module_init(specialize_sendto);
module_exit(restore_sendto);
