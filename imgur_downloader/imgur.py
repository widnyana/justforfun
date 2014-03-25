#!/usr/bin/env python
# imgur downloader.


import re
import os
from time import gmtime, strftime
from urllib2 import *


def main():
    chan = raw_input("Imgur Channel: ").strip()
    folder = ("%s/%s") % (chan, strftime("%Y-%m-%d", gmtime()))
    url = "http://imgur.com/r/%s" % chan

    try:
        os.makedirs(folder)
    except Exception:
        pass


    try:
        print "Extracting %s" % url
        html_page = urlopen(url)
        html_source = html_page.readlines()
        html_page.close()
        for line in html_source:
            p = re.compile(r'\/\/i.imgur.com\/[0-9a-zA-Z]+')
            iterator = p.finditer(line)

            for match in iterator:
                target = "http:%s.jpg" % (match.group()[:-1])
                name = "%s" % (match.group()[14:-1])
                print "Downloading %s..." % (target)
                saveto = "%s/%s" % (folder, name)

                reqObj = Request(target)
                try:
                    fileObj = urlopen(reqObj)
                    localFile = open(saveto, "wb")
                    localFile.write(fileObj.read())
                    localFile.close()
                except Exception:
                    print "Failed to download: %s" % (target)
                    pass

    except Exception, e:
        print e


if __name__ == '__main__':
    main()
