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
from glob import glob


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
    return os.path.getsize(path_to_file)

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

def bootstrap():
    parser = argparse.ArgumentParser(description=DESCRIPTION)
    parser.add_argument("--root", "-r", metavar="path",
                        help="the path to find log files in (defaults to current directory)")

    parsed_args = parser.parse_args()
    # main_val = 
    # return mainmain(root=parsed_args.root)
    print(mainmain(root=parsed_args.root))


def mainmain(root):
    listoffiles = [x for x in getListOfFiles('./results') if x.endswith('.gz')]
    ret = {}
    for i in listoffiles:
        ret[i] = outerextract(i)
    return ret

def outerextract(path_to_file):
    time = creation_date(path_to_file)
    if (os.path.exists('./results/' + str(time))  == False):
        my_tar = tarfile.open(path_to_file)
        my_tar.extractall('./results/' + str(time))
        my_tar.close()

    listoffiles = [x for x in getListOfFiles('./results/' + str(time) + '/results') if x.endswith('.gz')]
    ret = {}
    for i in listoffiles:
        ret[i] = middlextract(i, './results/' + str(time) + '/results')
    return ret


def middlextract(path_to_file, second_path):
    time = creation_date(path_to_file)
    if (os.path.exists(second_path + '/' + str(time)) == False):
        my_tar = tarfile.open(path_to_file)
        my_tar.extractall(second_path + '/' + str(time))
        my_tar.close()

    listoffiles = [x for x in getListOfFiles(second_path + '/' + str(time)) if x.endswith('.gz')]
    for i in listoffiles:
        lowerextract(i, second_path + '/' + str(time))

    ret = {}
    for i in glob(second_path + '/' + str(time) + "/*/"):
        if not i.endswith('conf/'):
            ret[i] = main(i)
    
    return ret


def lowerextract(path_to_file, second_path):
    time = creation_date(path_to_file)
    if (os.path.exists(second_path + '/' + str(time))  == False):
        my_tar = tarfile.open(path_to_file)
        my_tar.extractall(second_path + '/' + str(time))
        my_tar.close()
    
    listoffiles = [x for x in getListOfFiles(second_path + '/' + str(time) + '/collectl') if x.endswith('.gz')]
    for i in listoffiles:
        os.system('gunzip -k ' + i)
    

def nbench(root):
    if getListOfFiles(root + '/nbench') == "does not exist":
        return {}

    listoffiles = getListOfFiles(root + '/nbench')
    nbenchdict = {}
    for i in listoffiles:
        with open(i, 'r') as file:
            nbenchdict[i] = nbench_parser.main(iter(file))
    return nbenchdict

def radvisor(root):
    if getListOfFiles(root + '/radvisor') == "does not exist":
        return {}

    listoffiles = getListOfFiles(root + '/radvisor')
    radvisordict = {}
    for i in listoffiles:
        with open(i, 'r') as file:
            radvisordict[i] = radvisor_parser.main(iter(file))
    return radvisordict

def moby(root):
    if getListOfFiles(root + '/moby') == "does not exist":
        return {}


    listoffiles = getListOfFiles(root + '/moby')
    mobydict = {}
    for i in listoffiles:
        with open(i, 'r') as file:
            mobydict[i] = moby_parser.main(iter(file))
    return mobydict

def collectl_cpu(root):
    if getListOfFiles(root + '/collectl') == "does not exist":
        return {}

    listoffiles = [x for x in getListOfFiles(root + '/collectl') if x.endswith('cpu')]

    cpudict = {}

    for i in listoffiles:
        with open(i, 'r') as file:
            cpudict[i] = cpu.main(iter(file))
    return cpudict


def collectl_disk(root):
    if getListOfFiles(root + '/collectl') == "does not exist":
        return {}

    listoffiles = [x for x in getListOfFiles(root + '/collectl') if x.endswith('dsk')]

    dskdict = {}

    for i in listoffiles:
        with open(i, 'r') as file:
            dskdict[i] = disk.main(iter(file))
    return dskdict


def collectl_mem(root):
    if getListOfFiles(root + '/collectl') == "does not exist":
        return {}

    listoffiles = [x for x in getListOfFiles(root + '/collectl') if x.endswith('tab')]

    memdict = {}

    for i in listoffiles:
        with open(i, 'r') as file:
            memdict[i] = mem.main(iter(file))
    return memdict

# def config(root):
#     listoffiles = getListOfFiles("root")

#     if (len(listoffiles) == 0):
#         return {}

#     confdict = {}
#     for i in listoffiles:
#         with open(i, 'r') as file:
#             confdict[i] = config_parser.main(iter(file))
#     return confdict

def milliscope(root):

    if getListOfFiles(root + '/milliscope') == "does not exist":
        return {}


    spec_connect = {}
    spec_recvfrom = {}
    spec_sendto = {}

    with open(root + '/milliscope/spec_connect.csv', 'r') as file:
        spec_connect[root + '/milliscope/spec_connect.csv'] = milliscope_parser.spec_connect(iter(file))

    with open(root + '/milliscope/spec_recvfrom.csv', 'r') as file:
        spec_recvfrom[root + '/milliscope/spec_recvfrom.csv'] = milliscope_parser.main(iter(file))

    with open(root + '/milliscope/spec_sendto.csv', 'r') as file:
        spec_sendto[root + '/milliscope/spec_sendto.csv'] = milliscope_parser.main(iter(file))

    return (spec_connect, spec_recvfrom, spec_sendto)




def main(root):
    # create(root)

    #time = str(creation_date(root))
    nbench_val = nbench(root)
    moby_val = moby(root)
    radvisor_val = radvisor(root)
    collectl_cpu_val = collectl_cpu(root)
    collectl_disk_val = collectl_disk(root)
    collectl_mem_val = collectl_mem(root)
    (milliscope_vals) = milliscope(root)

    return (nbench_val, moby_val, radvisor_val, collectl_cpu_val, collectl_disk_val, collectl_mem_val, milliscope_vals)


if __name__ == "__main__":
    bootstrap()