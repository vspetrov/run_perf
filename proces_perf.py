#!/bin/python
import os, sys
import numpy as np

def process(rst_file):
    data = {}
    reading_params = False
    start_parse = False
    p = {}
    raw = []

    for l in open(rst_file).readlines():
        if l == "\n":
            continue
        if l == "params = {\n":
            p = {}
            reading_params = True
            continue

        if reading_params:
            if l == "}\n":
                reading_params = False
                continue

            v = l.split()
            p[v[0]] = v[2]
            continue

        v = l.split()
        if v[0] == "msgrange":
            start = int(v[1])
            end = int(v[2])
            msg=[start]
            while msg[-1] < end:
                msg.append(msg[-1] * 2)
            data['msg'] = np.array(msg)
            start_parse = True
            continue

        if not start_parse:
            continue

        if v[0] == "best:":
            b = [float(x) for x in v[1:]]
            data[".".join([k + "=" + p[k] for k in p])] = np.array(b)
            raw.append(b)

    raw = np.array(raw)
    data['best'] = raw.min(axis = 0)
    return data

def find_best(data, msgrange):
    start = np.where(data['msg'] == msgrange[0])[0]
    end = np.where(data['msg'] == msgrange[1])[0]
    scores = {}
    best=data['best']
    for k in data:
        if k == 'best' or k == 'msg':
            continue
        d = data[k]
        scores[k] = np.linalg.norm(best[start:end+1] - d[start:end+1])
    return scores

def print_sorted(data, msgrange, print_limit):
    scores = find_best(data, msgrange)
    printed = 0
    print "\n\n---------------------------------------------------------------------------"
    print "sorting for msgrange", msgrange, "\n"
    for v, k in sorted( ((v,k) for k,v in scores.iteritems())):
        print k, "\t\t\tscore =", v
        printed = printed + 1
        if printed == print_limit:
            break

    printed = 0
    print "\n\n", data['msg']
    print "\n", data['best'], "\n"
    for v, k in sorted( ((v,k) for k,v in scores.iteritems())):
        print data[k]
        printed = printed + 1
        if printed == print_limit:
            break

def main():
    rst_file = sys.argv[1]
    print_limit=10

    print "processing ", rst_file
    np.set_printoptions(linewidth=100, precision=2)

    data = process(rst_file)
    # msgrange=[4, 256]
    # scores = find_best(data, msgrange)

    print_sorted(data, [4, 128], print_limit)
    print_sorted(data, [256, 4096], print_limit)

if __name__ == '__main__':
    main()
