def decrypt(arg0, pwd):
    haystack = split(arg0, 3)
    haystack = [int(clean_leading_zero(x)) for x in haystack]
    length = len(haystack)
    txt_ret = ""
    num = 0
    for i in haystack:
        dek = i - num
        txt_ret += chr(dek)
        num += 1
    return txt_ret


def encrypt(arg0, pwd):
    txt_ret = ""
    for i in range(len(arg0)):
        asc = str(ord(arg0[i]))
        append = str(int(asc) + pwd + i)
        if len(append) == 1:
            append = "00" + append
        elif len(append) == 2:
            append = "0" + append
        elif len(append) == 3:
            append = append
        txt_ret += append
    return str(txt_ret)


def split(str, num):
    return [str[start:start + num] for start in range(0, len(str), num)]


def clean_leading_zero(string):
    clean = True
    while clean:
        if string.startswith("0"):
            string = string[1:]
        else:
            clean = False
    return string

txt = 'widnyana'
enc = encrypt(txt, 0)
dec = decrypt(enc, 0)

print "Text: {}\nEncrypted: {}\nDecrypted: {}".format(txt, enc, dec)
