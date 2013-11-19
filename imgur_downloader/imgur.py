#!/usr/bin/env python
# imgur downloader.


import re, urllib, urllib2, os
from time import gmtime, strftime

def main():
    chan = raw_input("Imgur Channel: ").strip()
    folder = ("%s/%s") % (chan, strftime("%Y-%m-%d", gmtime()))
    url = "http://imgur.com/r/%s" % chan

    try:
        os.makedirs(folder)
    except Exception, e:
        print e
        pass

    print "Extracting %s" % url

    html_page       = urllib2.urlopen(url)
    html_source     = html_page.readlines()
    html_page.close()
    for line in html_source:
        p = re.compile(r'\/\/i.imgur.com\/[0-9a-zA-Z]+')
        iterator = p.finditer(line)

        for match in iterator:
            target = "http:%s.jpg" %(match.group()[:-1])
            name = "%s" %(match.group()[14:-1])
            print "Downloading %s..." %(target)
            saveto = "%s/%s" % (folder, name)
            urllib.urlretrieve(target, saveto)

if __name__ == '__main__':
    main()