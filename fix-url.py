#! /usr/bin/env python
#
# fix-url.py ---
#
# Filename: fix-url.py
# Description:
# Author: Werther Zhang
# Maintainer:
# Created: Wed Mar 28 17:23:42 2018 (+0800)
#

# Change Log:
#
#

import os
import sys
import requests
import logging

_LOGGER = logging.getLogger(__name__)

def download_image(url, filename):
    _LOGGER.info("download {} to {}".format(url, filename))
    r = requests.get(url)
    with open(filename, 'w') as f:
        f.write(r.content)

def main(argc, argv):
    if argc != 3:
        _LOGGER.error("Invalid arguments")

    buffer = ""
    with open(argv[1], 'r') as f:
        buffer = f.read()

    basename = os.path.basename(argv[1])[:-3]
    _LOGGER.info('basename {}'.format(basename))
    index = 0
    for line in buffer.split('\n'):
        if line.find('leanote://file/getImage') == -1:
            with open(argv[2], 'w') as f:
                f.write(line + '\n')
        else:
            # replace leanote://file/ with http://pengzhangdev.tk:31119/api/file/ to download
            # replace http://pengzhangdev.tk:31119/api/file/getImage?fileId=xxx with https://pengzhangdev.github.io/assets/images/xxx.png to link to github
            start_pos = line.find("leanote://")
            end_pos = line.find(")")
            url = line[start_pos:end_pos].replace('leanote://', 'http://pengzhangdev.tk:31119/api/')
            originfname = line[start_pos:end_pos]
            targetfname = 'https://pengzhangdev.github.io/assets/images/' + basename + '-{}'.format(index) + '.png'
            downfname = os.path.join('docs/assets/images/', basename + '-{}'.format(index) + '.png')
            download_image(url, downfname)
            with open(argv[2], 'w+') as f:
                f.write(line.replace(originfname, targetfname) + '\n')
            index = index+1


if __name__ == '__main__':
    logging.basicConfig(level=logging.DEBUG)
    main(len(sys.argv), sys.argv)
