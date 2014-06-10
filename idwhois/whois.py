#!/usr/bin/env python

import sys
import requests
from lxml import etree


def main():
    if len(sys.argv) < 2:
        print "Domainnya mana gan?"
        quit()

    r = requests.post("https://www.pandi.or.id/whois/whois.php", data={
                      "domain": sys.argv[1], "submit": "Whois+Lookup"}, verify=False)
    data = etree.HTML(r.content)
    result = data.xpath("//pre//text()")
    if len(result) > 0:
        print "Domain Info:"
        print result[0]
        print "\nRegistrant Info:"
        print result[1]
    else:
        print "Data ga ketemu gan"

if '__main__' == __name__:
    main()
