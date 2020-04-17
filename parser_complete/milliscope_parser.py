import csv
import numpy
import sys
from collections import OrderedDict


class LogEntryConnect:
    """A TCP/IP event log entry."""

    def __init__(self, event, ret, ts, pid, tid, sock_fd, port):
        """Initialize a LogEntry.

        event -- [str] Name of the invoked syscall: 'connect', 'sendto', or 'recvfrom'.
        ts -- [int] Timestamp generated when the syscall was invoked.
        sock_fd -- [int] File descriptor of the socket used by the syscall.
        """
        self._event = event
        self._ret = ret
        self._ts = ts
        self._pid = pid
        self._tid = tid
        self._sock_fd = sock_fd
        self._port = port


    def __lt__(self, other):
        """Less than comparison operator.

        other -- [LogEntry] Another LogEntry being compared against this.
        """
        return self._ts < other._ts

    def event(self):
        """Return the name."""
        return self._event

    def ret(self):
        return self._ret

    def ts(self):
        """Return the timestamp."""
        return self._ts
    
    def pid(self):
        return self._pid

    def tid(self):
        return self._tid

    def sock_fd(self):
        """Return the socket file descriptor."""
        return self._sock_fd

    def port(self):
        return self._port

class LogEntry:
    """A TCP/IP event log entry."""

    def __init__(self, event, ret, ts, pid, tid, sock_fd):
        """Initialize a LogEntry.

        event -- [str] Name of the invoked syscall: 'connect', 'sendto', or 'recvfrom'.
        ts -- [int] Timestamp generated when the syscall was invoked.
        sock_fd -- [int] File descriptor of the socket used by the syscall.
        """
        self._event = event
        self._ret = ret
        self._ts = ts
        self._pid = pid
        self._tid = tid
        self._sock_fd = sock_fd


    def __lt__(self, other):
        """Less than comparison operator.

        other -- [LogEntry] Another LogEntry being compared against this.
        """
        return self._ts < other._ts

    def event(self):
        """Return the name."""
        return self._event

    def ret(self):
        return self._ret

    def ts(self):
        """Return the timestamp."""
        return self._ts
    
    def pid(self):
        return self._pid

    def tid(self):
        return self._tid

    def sock_fd(self):
        """Return the socket file descriptor."""
        return self._sock_fd

    # def __repr__(self):
    #     """Return a string representation."""
    #     return "[{event} -- TS: {ts}; SOCK_FD: {sock_fd}]".format(
    #         event=self._event, ts=str(self._ts), sock_fd=str(self._sock_fd))


def spec_connect(iterator):
    log_entries = OrderedDict()
    connect_reader = csv.DictReader(iterator)
    val = 0
    for connect_row in connect_reader:
        log_entries[val] = LogEntryConnect('connect', int(connect_row['RET']), int(connect_row['TS']), int(connect_row['PID']), int(connect_row['TID']), int(connect_row['SOCK_FD']), int(connect_row['PORT']))
        val = val + 1
    return log_entries

def main(iterator):
    log_entries = OrderedDict()
    connect_reader = csv.DictReader(iterator)
    val = 0
    for connect_row in connect_reader:
        log_entries[val] = LogEntry('connect', int(connect_row['RET']), int(connect_row['TS']), int(connect_row['PID']), int(connect_row['TID']), int(connect_row['SOCK_FD']))
        val = val + 1
    return log_entries