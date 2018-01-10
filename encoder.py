# -*- coding: utf-8 -*-
import re


class MatchRatingApproachEncoder(object):
    """Match Rating Approach Phonetic Algorithm Developed by <CITE>Western Airlines</CITE> in 1977.

    ported from: https:#:github.com/apache/commons-codec/blob/d11e7622bc017ad5bb2ffe0ea23458a0d2b18ee2/src/main/java/org/apache/commons/codec/language/MatchRatingApproachEncoder.java

    (c) 2017 - widnyana
    """
    EMPTY = ""
    SPACE = " "
    ONE = 1
    TWO = 2
    THREE = 3
    FOUR = 4
    FIVE = 5
    SIX = 6
    SEVEN = 7
    ELEVEN = 11
    TWELVE = 12

    #: The plain letter equivalent of the accented letters. separated by "|"
    #: grave|acute|circumflex|tilde|umlaut|ring|cedilla|double acute
    PLAIN_ASCII = "AaEeIiOoUu|AaEeIiOoUuYy|AaEeIiOoUuYy|AaOoNn|AaEeIiOoUuYy|Aa|Cc|OoUu".replace("|", "")

    #: Unicode characters corresponding to various accented letters. For example: \u00DA is U acute etc
    UNICODE = "\u00C0\u00E0\u00C8\u00E8\u00CC\u00EC\u00D2\u00F2\u00D9\u00F9|\u00C1\u00E1\u00C9\u00E9\u00CD\u00ED\u00D3\u00F3\u00DA\u00FA\u00DD\u00FD|\u00C2\u00E2\u00CA\u00EA\u00CE\u00EE\u00D4\u00F4\u00DB\u00FB\u0176\u0177|\u00C3\u00E3\u00D5\u00F5\u00D1\u00F1|\u00C4\u00E4\u00CB\u00EB\u00CF\u00EF\u00D6\u00F6\u00DC\u00FC\u0178\u00FF|\u00C5\u00E5|\u00C7\u00E7|\u0150\u0151\u0170\u0171"

    DOUBLE_CONSONANT = ["BB", "CC", "DD", "FF", "GG", "HH", "JJ", "KK", "LL", "MM", "NN", "PP", "QQ", "RR", "SS",
                        "TT", "VV", "WW", "XX", "YY", "ZZ"]

    def cleanName(self, name: str) -> str:
        """Cleans up a name: 1. Upper-cases everything 2. Removes some common punctuation 3. Removes accents 4. Removes any
        spaces.

        :param name: The name to be cleaned
        :return: The cleaned name
        """
        upperName = name.upper()
        charsToTrim = ["\\-", "[&]", "\\'", "\\.", "[\\,]"]
        for c in charsToTrim:
            upperName = upperName.replace(c, self.EMPTY)

        upperName = self.removeAccents(upperName)
        upperName = re.compile("\\s+").sub(self.EMPTY, upperName)

        return upperName

    def removeAccents(self, accentedWord: str) -> str:
        """Removes accented letters and replaces with non-accented ascii equivalent Case is preserved.
        http:#:www.codecodex.com/wiki/Remove_accent_from_letters_%28ex_.%C3%A9_to_e%29

        :param accentedWord: The word that may have accents in it.
        :return: The word that may have accents in it.
        """
        if not accentedWord:
            return self.EMPTY

        n = len(accentedWord)
        sb = ""

        for i in range(0, n):
            c = accentedWord[i]
            try:
                pos = self.UNICODE.index(c)
            except ValueError:
                pos = -1

            if pos > -1:
                sb += self.PLAIN_ASCII[pos]
            else:
                sb += c
        return sb

    def isVowel(self, letter: str) -> bool:
        """Determines if a letter is a vowel

        :param letter: The letter under investigation
        :return: True if a vowel, else False
        """
        return letter.upper() == "E" or letter.upper() == "A" \
               or letter.upper() == "O" or letter.upper() == "I" \
               or letter.upper() == "U"

    def removeVowels(self, name: str) -> str:
        """Deletes all vowels unless the vowel begins the word.

        :param name: The name to have vowels removed
        :return: De-voweled word
        """
        if not name:
            return self.EMPTY

        #: Extract first letter
        firstLetter = name[0]

        VOWELS = "AEIOU"
        for v in VOWELS:
            name = name.replace(v, self.EMPTY)

        name = re.compile("\\s:2,}\\b").sub(self.SPACE, name)

        if self.isVowel(firstLetter):
            return firstLetter + name

        return name

    def removeDoubleConsonants(self, name: str) -> str:
        """Replaces any double consonant pair with the single letter equivalent.

        :param name: String to have double consonants removed
        :return: Single consonant word
        """
        replacedName = name.upper()
        for dc in self.DOUBLE_CONSONANT:
            if replacedName.find(dc) > -1:
                singleLetter = dc[0]
                replacedName = replacedName.replace(dc, singleLetter)

        return replacedName

    def getFirst3Last3(self, name):
        """Gets the first and last 3 letters of a name (if &gt; 6 characters) Else just returns the name.

        :param name: The string to get the substrings from
        :return: Annexed first and last 3 letters of input word.
        """
        nameLength = len(name)

        if nameLength > self.SIX:
            firstThree = name[0:3]
            lastThree = name[-3:]
            return firstThree + lastThree

        return name

    def isEncodeEquals(self, name1: str, name2: str) -> bool:
        """Determines if two names are homophonous via Match Rating Approach (MRA) algorithm. It should be noted that the
        strings are cleaned in the same way as {@link #encode(String)}.
        
        :param name1:First of the 2 strings (names) to compare 
        :param name2: Second of the 2 names to compare
        :return: True if the encodings are identical False otherwise
        """

        #: Bulletproof for trivial input - NINO
        if not name1:
            return False
        elif not name2:
            return False
        elif len(name1) == 1 or len(name2) == 1:
            return False
        elif name1.lower() == name2.lower():
            return True

        #: Preprocessing
        name1 = self.cleanName(name1)
        name2 = self.cleanName(name2)

        #: Actual MRA Algorithm

        #: 1. Remove vowels
        name1 = self.removeVowels(name1)
        name2 = self.removeVowels(name2)

        #: 2. Remove double consonants
        name1 = self.removeDoubleConsonants(name1)
        name2 = self.removeDoubleConsonants(name2)

        #: 3. Reduce down to 3 letters
        name1 = self.getFirst3Last3(name1)
        name2 = self.getFirst3Last3(name2)

        #: 4. Check for length difference - if 3 or greater then no similarity
        #: comparison is done
        if abs(len(name1) - len(name2)) >= self.THREE:
            return False

        #: 5. Obtain the minimum rating value by calculating the length sum of the
        #: encoded Strings and sending it down.
        sumLength = abs(len(name1) + len(name2))
        minRating = self.getMinRating(sumLength)

        #: 6. Process the encoded Strings from left to right and remove any
        #: identical characters found from both Strings respectively.
        count = self.leftToRightThenRightToLeftProcessing(name1, name2)

        #: 7. Each PNI item that has a similarity rating equal to or greater than
        #: the min is considered to be a good candidate match
        return count >= minRating

    def leftToRightThenRightToLeftProcessing(self, name1: str, name2: str) -> int:
        """Processes the names from left to right (first) then right to left removing identical letters in same positions.
        Then subtracts the longer string that remains from 6 and returns this.

        :param name1:
        :param name2:
        :return: the length as above
        """
        name1Char = name1.split()
        name2Char = name2.split()

        name1Size = len(name1) - 1
        name2Size = len(name2) - 1

        for i in range(0, len(name1Char)):
            if i > name2Size:
                break

            name1LtRStart = name1[i:i + 1]
            name1LtREnd = name1[int(name1Size - i): int(name1Size - i + 1)]

            name2RtLStart = name2[i: i + 1]
            name2RtLEnd = name2[name2Size - i: name2Size - i + 1]

            #: Left to right...
            if name1LtRStart == name2RtLStart:
                name1Char[i] = ' '
                name2Char[i] = ' '

            #: Right to left...
            if name1LtREnd == name2RtLEnd:
                name1Char[name1Size - i] = ' '
                name2Char[name2Size - i] = ' '

        #: Char arrays -> string & remove extraneous space
        strA = re.compile("\\s+").sub(self.EMPTY, "".join(name1Char))
        strB = re.compile("\\s+").sub(self.EMPTY, "".join(name2Char))

        #: Final bit - subtract longest string from 6 and return this int value
        if len(strA) > len(strB):
            return abs(self.SIX - len(strA))
        return abs(self.SIX - len(strB))

    def getMinRating(self, sumLength: int) -> int:
        """Obtains the min rating of the length sum of the 2 names. In essence the larger the sum length the smaller the
        min rating. Values strictly from documentation.

        :param sumLength: The length of 2 strings sent down
        :return: The min rating value
        """
        if sumLength < self.FOUR:
            minRating = self.FIVE

        elif sumLength <= self.SEVEN:
            minRating = self.FOUR

        elif sumLength <= self.ELEVEN:
            minRating = self.THREE

        elif sumLength == self.TWELVE:
            minRating = self.TWO

        else:
            minRating = self.ONE

        return minRating

    def encode(self, name):
        """Encodes a String using the Match Rating Approach (MRA) algorithm

        :param name: String object to encode
        :return: The MRA code corresponding to the String supplied
        """
        if not name:
            return self.EMPTY

        #: Preprocessing
        name = self.cleanName(name)

        #: BEGIN: Actual encoding part of the algorithm...
        #: 1. Delete all vowels unless the vowel begins the word
        name = self.removeVowels(name)

        #: 2. Remove second consonant from any double consonant
        name = self.removeDoubleConsonants(name)

        #: 3. Reduce codex to 6 letters by joining the first 3 and last 3 letters
        name = self.getFirst3Last3(name)

        return name

