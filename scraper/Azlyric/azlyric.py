#!/usr/bin/env python
# -*- Coding: utf-8 -*-
#         DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#                 Version 2, December 2004

# Copyright (C) 2014  widnyana - sapiterbangID Labs

# Everyone is permitted to copy and distribute verbatim or modified
# copies of this license document, and changing it is allowed as long
# as the name is changed.

#         DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
# TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION

# 0. You just DO WHAT THE FUCK YOU WANT TO.


import sys
import requests
try:
    from bs4 import BeautifulSoup as soup
except ImportError:
    print """
    You need BeautifulSoup4 module
    to make this class working"""
    sys.exit()


class AzLyrics(object):

    def __init__(self):
        self.searchURI = "http://search.azlyrics.com/search.php?"

    def search(self, string=None):
        self.string = string
        # TODO: complete this method
        pass

    def get_html(self, url):
        html = requests.get(url)
        meh = soup(html.text)
        html.close()

        return meh

    def get_lyric(self, url):
        meh = self.get_html(url)
        data = {}
        data['title'] = meh.title.string
        data['lyric'] = meh.select('div[style*="margin-left:10px"]')[0].text.replace(
            "\n", "").replace("\r", "")

        return data
