import tarfile
import os
import platform
import sys
import numpy as np
from dateutil import parser
from collections import OrderedDict
from more_itertools import peekable
import glob, json, csv, argparse
from csv import Error
import re
from decimal import Decimal
import gzip
import glob


import nbench_parser
import radvisor_parser
import moby_parser
import config_parser
import cpu
import disk
import mem
import milliscope_parser

DESCRIPTION = "Script to parse rAdvisor container stat logs"

def creation_date(path_to_file):
    # if platform.system() == 'Windows':
    return os.path.getsize(path_to_file)
    # else:
    #     stat = os.stat(path_to_file)
    #     try:
    #         return stat.st_birthtime
    #     except AttributeError:
    #         return stat.st_mtime

def check_if_exists(path_to_file):
    time = str(creation_date(path_to_file))
    return os.path.exists(time)

def getListOfFiles(dirName):
    try:
        listOfFile = os.listdir(dirName)
    except:
        return "does not exist"
    allFiles = list()
    for entry in listOfFile:
        fullPath = os.path.join(dirName, entry)
        if os.path.isdir(fullPath):
            allFiles = allFiles + getListOfFiles(fullPath)
        else:
            allFiles.append(fullPath)     
    return allFiles

def create_folder(path_to_file):
    time = creation_date(path_to_file)
    my_tar = tarfile.open(path_to_file)
    my_tar.extractall('./' + str(time))
    my_tar.close()

    path = "./" + str(time) +  "/collectl"
    if getListOfFiles(path) == "does not exist":
        return

    listOfFiles = getListOfFiles(path)

    for entry in listOfFiles:
        os.system('gunzip -k ' + entry)


def create(path_to_file):
    if (check_if_exists(path_to_file)):
        return
    create_folder(path_to_file)

def bootstrap():
    parser = argparse.ArgumentParser(description=DESCRIPTION)
    parser.add_argument("--root", "-r", metavar="path",
                        help="the path to find log files in (defaults to current directory)")

    parsed_args = parser.parse_args()

    main_val = mainmain(root=parsed_args.root)
    config_val = config()
    return(config_val, main_val)


def mainmain(root):
    my_tar = tarfile.open(root)
    my_tar.extractall('./results')
    my_tar.close()

    listoffiles = [x for x in getListOfFiles('./results') if x.endswith('.gz')]
    ret = {}
    for i in listoffiles:
        ret[i] = main(i)
    return ret
    
    


def nbench(time):
    if getListOfFiles(time + '/nbench') == "does not exist":
        return {}

    listoffiles = getListOfFiles(time + '/nbench')
    nbenchdict = {}
    for i in listoffiles:
        with open(i, 'r') as file:
            nbenchdict[i] = nbench_parser.main(iter(file))
    return nbenchdict

def radvisor(time):
    if getListOfFiles(time + '/radvisor') == "does not exist":
        return {}

    listoffiles = getListOfFiles(time + '/radvisor')
    radvisordict = {}
    for i in listoffiles:
        with open(i, 'r') as file:
            radvisordict[i] = radvisor_parser.main(iter(file))
    return radvisordict

def moby(time):
    if getListOfFiles(time + '/moby') == "does not exist":
        return {}


    listoffiles = getListOfFiles(time + '/moby')
    mobydict = {}
    for i in listoffiles:
        with open(i, 'r') as file:
            mobydict[i] = moby_parser.main(iter(file))
    return mobydict

def collectl_cpu(time):
    if getListOfFiles(time + '/collectl') == "does not exist":
        return {}

    listoffiles = [x for x in getListOfFiles(time + '/collectl') if x.endswith('cpu')]

    cpudict = {}

    for i in listoffiles:
        with open(i, 'r') as file:
            cpudict[i] = cpu.main(iter(file))
    #print(cpudict)
    return cpudict


def collectl_disk(time):
    if getListOfFiles(time + '/collectl') == "does not exist":
        return {}

    listoffiles = [x for x in getListOfFiles(time + '/collectl') if x.endswith('dsk')]

    dskdict = {}

    for i in listoffiles:
        with open(i, 'r') as file:
            dskdict[i] = disk.main(iter(file))
    #print(cpudict)
    return dskdict


def collectl_mem(time):
    if getListOfFiles(time + '/collectl') == "does not exist":
        return {}

    listoffiles = [x for x in getListOfFiles(time + '/collectl') if x.endswith('tab')]

    memdict = {}

    for i in listoffiles:
        with open(i, 'r') as file:
            memdict[i] = mem.main(iter(file))
    #print(cpudict)
    return memdict


def config():
    listoffiles = getListOfFiles("results/conf")
    confdict = {}
    for i in listoffiles:
        with open(i, 'r') as file:
            confdict[i] = config_parser.main(iter(file))
    return confdict

def milliscope(time):

    if getListOfFiles(time + '/milliscope') == "does not exist":
        return {}


    spec_connect = {}
    spec_recvfrom = {}
    spec_sendto = {}

    with open(time + '/milliscope/spec_connect.csv', 'r') as file:
        spec_connect[time + '/milliscope/spec_connect.csv'] = milliscope_parser.spec_connect(iter(file))

    with open(time + '/milliscope/spec_recvfrom.csv', 'r') as file:
        spec_recvfrom[time + '/milliscope/spec_recvfrom.csv'] = milliscope_parser.main(iter(file))

    with open(time + '/milliscope/spec_sendto.csv', 'r') as file:
        spec_sendto[time + '/milliscope/spec_sendto.csv'] = milliscope_parser.main(iter(file))

    return (spec_connect, spec_recvfrom, spec_sendto)




def main(root):
    create(root)

    time = str(creation_date(root))
    nbench_val = nbench(time)
    moby_val = moby(time)
    radvisor_val = radvisor(time)
    collectl_cpu_val = collectl_cpu(time)
    collectl_disk_val = collectl_disk(time)
    collectl_mem_val = collectl_mem(time)
    (milliscope_vals) = milliscope(time)

    return (nbench_val, moby_val, radvisor_val, collectl_cpu_val, collectl_disk_val, collectl_mem_val, milliscope_vals)


if __name__ == "__main__":
    bootstrap()