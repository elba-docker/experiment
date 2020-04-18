import datetime
import numpy
import sys
from collections import OrderedDict


class MemEntry:
    """A memory entry."""

    def __init__(self, tot, used, timestamp):
        """Initialize a MemEntry."""
        self._tot = tot
        self._used = used
        self._timestamp = timestamp


def main(iterator):
    # List of timestamps and MemEntry.
    timestamps = []
    mem_entries = OrderedDict()
    # Process memory raw file.
    for mem_line in iterator:
        # Check if it is a comment.
        if mem_line[0] == '#':
            continue
        mem_entry_data = mem_line.split()
        timestamp = datetime.datetime.strptime(mem_entry_data[1], "%H:%M:%S.%f")
        mem_entries[timestamp] = MemEntry(int(mem_entry_data[2]), int(mem_entry_data[3]), timestamp)
    return mem_entries