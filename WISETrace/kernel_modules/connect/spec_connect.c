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
MODULE_DESCRIPTION("Specialize connect syscall.");
MODULE_VERSION("0.1");

#define CONNECT_BUFF_SIZE 524288
#define MAX_CONNECT_LOG_ENTRY_LEN 512

typedef struct connect_buff_entry {
  long long ts;               /* Timestamp */
  int ret;                    /* Return value */
  int pid;                    /* Process ID */
  int tid;                    /* Thread ID */
  int sock_fd;                /* Socket file descriptor */
  unsigned short port;        /* Port (in network byte order) */
} t_connect_buff_entry;
static t_connect_buff_entry connect_buff[CONNECT_BUFF_SIZE];
static atomic_t connect_buff_count;

int connect_proc_read(struct file *proc, char __user *buff, unsigned long len,
    long long *offset) {
  char log_entry[MAX_CONNECT_LOG_ENTRY_LEN];
  int log_entry_len;
  int copied_len = 0;
  t_connect_buff_entry *buff_entry;

  if (*offset == 0) {
    log_entry_len = sprintf(log_entry, "RET,TS,PID,TID,SOCK_FD,PORT\n");
    copy_to_user(buff + copied_len, log_entry, log_entry_len);
    copied_len += log_entry_len;
  }
  while (*offset < CONNECT_BUFF_SIZE && *offset < atomic_read(&connect_buff_count)) {
    buff_entry = &connect_buff[*offset];
    log_entry_len = sprintf(log_entry, "%d,%lld,%d,%d,%d,%hu\n",
        buff_entry->ret, buff_entry->ts, buff_entry->pid, buff_entry->tid,
        buff_entry->sock_fd, ntohs(buff_entry->port));
    if (copied_len + log_entry_len >= len)
      break;
    copy_to_user(buff + copied_len, log_entry, log_entry_len);
    copied_len += log_entry_len;
    *offset += 1;
  }
  return copied_len;
}

asmlinkage long (*original_connect)(int, struct sockaddr __user *, int);

asmlinkage long specialized_connect(int fd, struct sockaddr __user *uservaddr,
    int addrlen) {
  int buff_entry_idx;
  struct timeval ts;
  struct sockaddr_in *addr_in;
  struct sockaddr_in6 *addr_in6;
  t_connect_buff_entry *buff_entry = NULL;

  buff_entry_idx = atomic_add_return(1, &connect_buff_count) - 1;
  if (buff_entry_idx < CONNECT_BUFF_SIZE) {
    do_gettimeofday(&ts);
    buff_entry = &connect_buff[buff_entry_idx];
    buff_entry->ts = ts.tv_sec * 1000000LL + ts.tv_usec;
    buff_entry->pid = task_tgid_nr(current);
    buff_entry->tid = task_pid_nr(current);
    buff_entry->sock_fd = fd;
    if (uservaddr && uservaddr->sa_family == AF_INET) {
      addr_in = (struct sockaddr_in *) uservaddr;
      buff_entry->port = addr_in->sin_port;
    }
    else if (uservaddr && uservaddr->sa_family == AF_INET6) {
      addr_in6 = (struct sockaddr_in6 *) uservaddr;
      buff_entry->port = addr_in6->sin6_port;
    }
    return (buff_entry->ret = original_connect(fd, uservaddr, addrlen));
  }
  return original_connect(fd, uservaddr, addrlen);
}

static const struct file_operations connect_proc_ops = {
  .read = (void *) connect_proc_read
};
static struct proc_dir_entry *connect_proc_dir_entry;

static int __init specialize_connect(void) {
  atomic_set(&connect_buff_count, 0);
  connect_proc_dir_entry = proc_create("spec_connect", 0, NULL,
      &connect_proc_ops);
  original_connect = (void *) sys_call_table[__NR_connect];
  sys_call_table[__NR_connect] = (void *) &specialized_connect;

  printk(KERN_INFO "Specialized connect syscall.\n");

  return 0;
}

static void __exit restore_connect(void) {
  sys_call_table[__NR_connect] = (void *) original_connect;
  proc_remove(connect_proc_dir_entry);

  printk(KERN_INFO "Restored connect syscall.\n");
}

module_init(specialize_connect);
module_exit(restore_connect);
