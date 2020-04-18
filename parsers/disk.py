import datetime
import sys
from collections import OrderedDict


class DiskEntry:
    """A disk entry."""

    def __init__(self, read_in_kb, write_in_kb, timestamp):
        """Initialize a DiskEntry."""
        self._read_in_kb = read_in_kb
        self._write_in_kb = write_in_kb
        self._timestamp = timestamp

    def read_in_kb(self):
        return self._read_in_kb

    def write_in_kb(self):
        return self._write_in_kb
    
    def timestamp(self):
        return self._timestamp

def main(iterator):
    # List of timestamps and DiskEntry.
    timestamps = []
    disk_entries = OrderedDict()
    # Process disk raw file.
    for disk_line in iterator:
        # Check if it is a comment.
        if disk_line[0] == '#':
            continue
        disk_entry_data = disk_line.split()
        timestamp = datetime.datetime.strptime(disk_entry_data[1], "%H:%M:%S.%f")
        total_read_in_kb = 0
        total_write_in_kb = 0
        for disk_no in range((len(disk_entry_data) - 2) // 14):
            total_read_in_kb += int(disk_entry_data[disk_no * 14 + 5])
            total_write_in_kb += int(disk_entry_data[disk_no * 14 + 9])
            # if len(disk_entries) < disk_no + 1:
            #     disk_entries.append(OrderedDict())
        disk_entries[timestamp] = DiskEntry(total_read_in_kb, total_write_in_kb, timestamp)
    return disk_entries