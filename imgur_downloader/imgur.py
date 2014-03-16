#!/usr/bin/env python
# imgur downloader.


import re, urllib, os
from time import gmtime, strftime
from urllib2 import *
import argparse


class ImgurDownloader():
    def choose(self):
        parser = argparse.ArgumentParser()
        parser.add_argument("-m", "--mode", help="\nuse 'chan' for Downloading a channel (imgur.com/r/channelname)\nor use 'album'for Downloading an album (imgur.com/a/albumname")
        args = vars(parser.parse_args())

        if args['mode'] == 'chan':
            self.channelD()
        if args['mode'] == 'album':
            self.album()

    def album(self):
        print "Imgur album downloader"
        chan = raw_input("Imgur Channel: ").strip()
        folder = ("%s/%s") % (chan, strftime("%Y-%m-%d", gmtime()))
        url = "http://imgur.com/a/%s" % chan

        try:
            os.makedirs(folder)
        except Exception, e:
            pass

        print "Extracting %s" % url

        try:
            html_page       = urlopen(url)
        except Exception, e:
            print '''\n\nAlbum Not Found\nQuiting...
                '''

        html_source     = html_page.readlines()
        html_page.close()
        download = []

        for line in html_source:
            p = re.compile(r'http:\/\/i.imgur.com\/[.0-9a-zA-Z]+')
            iterator = p.finditer(line)

            for match in iterator:
                target = '%s' %(match.group())

                if target not in download:
                    download.append(target)


        for url in download:
            print "Downloading %s..." %(url)
            saveto = "%s/%s" % (folder, url[19:])

            reqObj  = Request(url)
            fileObj = urlopen(reqObj)

            localFile   = open(saveto, "wb")
            localFile.write(fileObj.read())
            localFile.close()

        print "\n Done :)"

    def channelD(self):
        chan = raw_input("Imgur Channel: ").strip()
        folder = ("%s/%s") % (chan, strftime("%Y-%m-%d", gmtime()))
        url = "http://imgur.com/r/%s" % chan

        try:
            os.makedirs(folder)
        except Exception, e:
            pass

        print "Extracting %s" % url

        html_page       = urlopen(url)
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

                reqObj  = Request(target)
                fileObj = urlopen(reqObj)

                localFile   = open(saveto, "wb")
                localFile.write(fileObj.read())
                localFile.close()



if __name__ == '__main__':
    obj = ImgurDownloader()
    obj.choose()
