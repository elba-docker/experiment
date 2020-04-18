"""
Script to parse nbench logs
"""

import numpy as np
from dateutil import parser
from collections import OrderedDict
from more_itertools import peekable
import glob, os, json, csv, argparse
from csv import Error
import re
from decimal import Decimal


DESCRIPTION = "Script to parse nbench logs"

def main(iterator):
    """
    Loads an output file from rAdvisor into an ordered dictionary
    of read timestamp (int) -> LogEntry in the order of logging
    """

    entries = OrderedDict()
    for line in iterator:

        if "START" in line:
            entries.update({"start_time":int(re.search(r'\d+', line).group())})
        if "STOP" in line:
            entries.update({"end_time":int(re.search(r'\d+', line).group())})
        if "NUMERIC SORT" in line and "Done with" not in line:
            #print(float(re.search(r'\d+', line).group()))
            entries.update({"numeric_sort":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            entries.update({"numeric_sort_abs_sdv":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"numeric_sort_rel_sdv":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"numeric_sort_num_runs":int(re.search(r'\d+', line).group())})
            line = next(iterator)
            
            entries.update({"numeric_sort_num_arrs":int(re.search(r'\d+', line).group())})
            line = next(iterator)
            
            entries.update({"numeric_sort_arr_size":int(re.search(r'\d+', line).group())})

        if "STRING SORT" in line and "Done with" not in line:
            #print(float(re.search(r'\d+', line).group()))
            entries.update({"string_sort":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"string_sort_abs_sdv":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"string_sort_rel_sdv":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"string_sort_num_runs":int(re.search(r'\d+', line).group())})
            line = next(iterator)
            
            entries.update({"string_sort_num_arrs":int(re.search(r'\d+', line).group())})
            line = next(iterator)
            
            entries.update({"string_sort_arr_size":int(re.search(r'\d+', line).group())})

        if "STRING SORT" in line and "Done with" not in line:
            #print(float(re.search(r'\d+', line).group()))
            entries.update({"string_sort":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"string_sort_abs_sdv":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"string_sort_rel_sdv":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"string_sort_num_runs":int(re.search(r'\d+', line).group())})
            line = next(iterator)
            
            entries.update({"string_sort_num_arrs":int(re.search(r'\d+', line).group())})
            line = next(iterator)
            
            entries.update({"string_sort_arr_size":int(re.search(r'\d+', line).group())})

        if "BITFIELD" in line and "Done with" not in line:
            #print(float(re.search(r'\d+', line).group()))
            entries.update({"bitfield":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"bitfield_abs_sdv":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"bitfield_rel_sdv":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"bitfield_num_runs":int(re.search(r'\d+', line).group())})
            line = next(iterator)
            
            entries.update({"bitfield_ops_arr_size":int(re.search(r'\d+', line).group())})
            line = next(iterator)
            
            entries.update({"bitfield_arr_size":int(re.search(r'\d+', line).group())})

        if "FP EMULATION" in line and "Done with" not in line:
            #print(float(re.search(r'\d+', line).group()))
            entries.update({"fp_emul":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"fp_emul_abs_sdv":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"fp_emul_rel_sdv":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"fp_emul_num_runs":int(re.search(r'\d+', line).group())})
            line = next(iterator)
            
            entries.update({"fp_emul_num_loops":int(re.search(r'\d+', line).group())})
            line = next(iterator)
            
            entries.update({"fp_emul_arr_size":int(re.search(r'\d+', line).group())})

        if "FOURIER" in line and "Done with" not in line:
            #print(float(re.search(r'\d+', line).group()))
            entries.update({"fourier":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"fourier_abs_sdv":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"fourier_rel_sdv":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"fourier_num_runs":int(re.search(r'\d+', line).group())})
            line = next(iterator)
            
            entries.update({"fourier_num_coef":int(re.search(r'\d+', line).group())})

        if "ASSIGNMENT" in line and "Done with" not in line:
            #print(float(re.search(r'\d+', line).group()))
            entries.update({"assignment":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            entries.update({"assignment_abs_sdv":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"assignment_rel_sdv":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"assignment_num_runs":int(re.search(r'\d+', line).group())})
            line = next(iterator)
            
            entries.update({"assignment_num_arrs":int(re.search(r'\d+', line).group())})

        if "IDEA" in line and "Done with" not in line:
            #print(float(re.search(r'\d+', line).group()))
            entries.update({"idea":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"idea_abs_sdv":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"idea_rel_sdv":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"idea_num_runs":int(re.search(r'\d+', line).group())})
            line = next(iterator)
            
            entries.update({"idea_arr_size":int(re.search(r'\d+', line).group())})
            line = next(iterator)
            
            entries.update({"idea_num_loops":int(re.search(r'\d+', line).group())})
        
        if "HUFFMAN" in line and "Done with" not in line:
            #print(float(re.search(r'\d+', line).group()))
            entries.update({"huffman":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"huffman_abs_sdv":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"huffman_rel_sdv":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"huffman_num_runs":int(re.search(r'\d+', line).group())})
            line = next(iterator)
            
            entries.update({"huffman_arr_size":int(re.search(r'\d+', line).group())})
            line = next(iterator)
            
            entries.update({"huffman_num_loops":int(re.search(r'\d+', line).group())})


        if "NEURAL NET" in line and "Done with" not in line:
            #print(float(re.search(r'\d+', line).group()))
            entries.update({"nnet":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"nnet_abs_sdv":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"nnet_rel_sdv":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"nnet_num_runs":int(re.search(r'\d+', line).group())})
            line = next(iterator)
            
            entries.update({"nnet_num_loops":int(re.search(r'\d+', line).group())})

        if "LU DECOMPOSITION" in line and "Done with" not in line:
            #print(float(re.search(r'\d+', line).group()))
            entries.update({"lu_decomp":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"lu_decomp_abs_sdv":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"lu_decomp_rel_sdv":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"lu_decomp_num_runs":int(re.search(r'\d+', line).group())})
            line = next(iterator)
            
            entries.update({"lu_decomp_num_arrs":int(re.search(r'\d+', line).group())})

        if "libc" in line and "Baseline" not in line and "*" not in line:
            line = next(iterator)
            
            entries.update({"memory_index":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"integer_index":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})
            line = next(iterator)
            
            entries.update({"float_index":float(re.search(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?", line).group())})

    #print(entries)
    return entries

if __name__ == "__main__":
    main()