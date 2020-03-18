import numpy as np
import pandas as pd
from dateutil import parser
from collections import OrderedDict
import glob, os, json

DIR = "./logs/v0"
DATE_FORMAT = "%Y-%m-%dT%H:%M:%S.%fZ"
write_timestamps = {}
read_timestamps = {}
log_entries = {}
files = []

os.chdir(DIR)
for file in glob.glob("*.log"):
    files.append(file)

# from https://stackoverflow.com/a/2400875
def diffs(t):
    return [j-i for i, j in zip(t[:-1], t[1:])]

def aggregate(d):
    l = []
    prev = None
    count = 0
    for entry in d:
        if prev == entry:
            count += 1
        else:
            prev = entry
            l.append(count)
            count = 1
    return l

for file in files:
    write_timestamp_list = []
    read_timestamp_list = []
    log_entry_dict = OrderedDict()
    with open(file, "r") as output:
        print(f"Parsing {file}")
        num = 0
        for line in output:
            num += 1
            if len(line.strip()) > 0:
                timestamp_pos = line.find(" ")
                timestamp = int(line[:timestamp_pos])
                write_timestamp_list.append(timestamp)
                content = line[timestamp_pos + 1:].strip()
                try:
                    json_content = json.loads(content)
                    log_entry_dict[timestamp] = json_content
                    read_timestamp_list.append(parser.isoparse(json_content["read"]))
                except json.decoder.JSONDecodeError as err:
                    print(content)
                    print(num)
                    print(err)

    write_timestamps[file] = write_timestamp_list
    read_timestamps[file] = read_timestamp_list
    log_entries[file] = log_entry_dict

def getOr(d, key, fallback):
    if key in d:
        return d[key]
    else:
        return fallback

def get_deltas(ts):
    sorted_ts = sorted(ts)
    min_ts = min(sorted_ts)
    relative = list(t - min_ts for t in sorted_ts)
    return diffs(relative)

print(f"Done parsing {len(files)} files")
for file in files:
    wdeltas = get_deltas(float(t) / 1E6 for t in write_timestamps[file])
    rdeltas = get_deltas(dt.timestamp() * 1000 for dt in read_timestamps[file])

    print(f'Deltas for {file}:')
    deltas_df = pd.DataFrame({'Write Deltas (ms)': wdeltas, 'Read Deltas (ms)': rdeltas})
    print(deltas_df.describe(include='all'))
    print("\n")

    data = log_entries[file]

    df = {
        'total_usage': [data[t]['cpu_stats']['cpu_usage']['total_usage'] for t in data],
        'pre_total_usage': [data[t]['precpu_stats']['cpu_usage']['total_usage'] for t in data],
        'usage': [getOr(data[t]['memory_stats'], 'usage', 0) for t in data]
    }

    aggregate_df = {k: aggregate(diffs(d)) for k, d in df.items()}
    for k, l in aggregate_df.items():
        df_dict = {}
        df_dict[f"average time (*period) between change {k}"] = l
        specific_df = pd.DataFrame(df_dict)
        print(specific_df.describe(include='all'))

    print("\n====================================================================================================\n")