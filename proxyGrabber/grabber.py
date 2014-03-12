#!/usr/bin/env python
# simple proxy grabber from xroxy.com
# requested by twitter.com/massusant
#

#        DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#                    Version 2, December 2004

# Copyright (C) 2014 Widnyana <widnyana.p gmail com>

# Everyone is permitted to copy and distribute verbatim or modified
# copies of this license document, and changing it is allowed as long
# as the name is changed.

#            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION

#  0. You just DO WHAT THE FUCK YOU WANT TO.


import re
import urllib2

def grabIp():

    page = 0
    ipNum = 0

    while page < 17:

        url         = "http://www.xroxy.com/proxylist.php?port=&type=All_http&ssl=&country=&latency=1000&pnum=%s#table" % page
        request     = urllib2.Request(url)
        request.add_header("User-Agent","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/33.0.1750.117 Safari/537.36")
        opener      = urllib2.build_opener()
        feed        = opener.open(request).readlines()


        for line in feed:
            p   = re.compile(r'host=\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}')
            iterator = p.finditer(line)

            for match in iterator:
                print "'%s'," % match.group()[5:]
                ipNum += 1

        page += 1

    print "\nDone. we have %d ip(s)" % ipNum



if __name__ == '__main__':
    grabIp()