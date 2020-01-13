# -*- coding: utf-8 -*-
import json
import requests
from lxml import html

SOURCE_URL = """http://www.useragentstring.com/pages/useragentstring.php?typ=Browser"""
XPATH = """//div[@id='content']/div[@id='liste']/ul/li/a//text()"""


def fetch_url():
    content = requests.get(SOURCE_URL).content
    dom = html.fromstring(content)
    ua = dom.xpath(XPATH)
    return ua


if __name__ == '__main__':
    ua = fetch_url()
    print (f"UserAgent string found: {len(ua)}")
    
    with open("ua_1.json", "w") as f:
        f.write(json.dumps(ua))