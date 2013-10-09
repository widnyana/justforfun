#!/usr/bin/env python
# imgur downloader.


import re, urllib, urllib2

url = raw_input("Imgur url: ").strip()
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
        print "Downloading %s ..." %(target)
        urllib.urlretrieve(target, name)
