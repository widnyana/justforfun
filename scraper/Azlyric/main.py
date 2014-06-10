#!/usr/bin/env python
# -*- Coding: utf-8 -*-
from azlyric import AzLyrics


if __name__ == '__main__':
    az = AzLyrics()
    print az.get_lyric("http://www.azlyrics.com/lyrics/falloutboy/youngvolcanoes.html")
