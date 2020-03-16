import numpy as np
import pandas as pd
from collections import OrderedDict
import glob, os, json

DIR = "./logs"
timestamps = {}
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
    timestamp_list = []
    log_entry_dict = OrderedDict()
    with open(file, "r") as output:
        print(f"Parsing {file}")
        num = 0
        for line in output:
            num += 1
            if len(line.strip()) > 0:
                timestamp_pos = line.find(" ")
                timestamp = int(line[:timestamp_pos])
                timestamp_list.append(timestamp)
                content = line[timestamp_pos + 1:].strip()
                try:
                    log_entry_dict[timestamp] = json.loads(content)
                except json.decoder.JSONDecodeError as err:
                    print(content)
                    print(num)
                    print(err)

    timestamps[file] = timestamp_list
    log_entries[file] = log_entry_dict

def getOr(d, key, fallback):
    if key in d:
        return d[key]
    else:
        return fallback

print(f"Done parsing {len(files)} files")
for file in files:
    ts = sorted(t / 1E6 for t in timestamps[file])
    min_ts = min(ts)
    relative = list(int(t - min_ts) for t in ts)
    deltas = diffs(relative)

    print(f'Deltas for {file}:')
    deltas_df = pd.DataFrame({'Deltas': deltas})
    print(deltas_df.describe(include='all'))
    print("\n")

    data = log_entries[file]

    df = {
        'total_usage': [data[t]['cpu_stats']['cpu_usage']['total_usage'] for t in data],
        'pre_total_usage': [data[t]['precpu_stats']['cpu_usage']['total_usage'] for t in data],
        'usage': [getOr(data[t]['memory_stats'], 'usage', 0) for t in data]
    }


    diffs_df = {k: diffs(d) for k, d in df.items()}
    aggregate_df = {k: aggregate(d) for k, d in diffs_df.items()}

    for k, l in aggregate_df.items():
        df_dict = {}
        df_dict[f"average time (*period) between change {k}"] = l
        specific_df = pd.DataFrame(df_dict)
        print(specific_df.describe(include='all'))

    print("\n====================================================================================================\n")