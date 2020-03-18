import numpy as np
import pandas as pd

FILE = "output.txt"
OFFSET = len("timestamp") + 1
TARGET_NAME = "vibrant_khorana"
timestamps = []

# from https://stackoverflow.com/a/2400875
def diffs(t):
    return [j-i for i, j in zip(t[:-1], t[1:])]

with open(FILE, "r") as output:
    for line in output:
        if line.startswith(f"cName={TARGET_NAME}"):
            components = line.split()
            for component in components:
                if component.startswith("timestamp"):
                    timestamps.append(int(component[OFFSET:]))

timestamps = sorted(t / 1E6 for t in timestamps)
min_ts = min(timestamps)
relative = list(int(t - min_ts) for t in timestamps)
deltas = diffs(relative)

print('Deltas:')
deltas_df = pd.DataFrame({'Deltas': deltas})
print(deltas_df.describe(include='all'))
