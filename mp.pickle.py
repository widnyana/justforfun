# -*- coding: utf-8 -*-
"""
a recipe to handle error like this
PicklingError: Can't pickle <type 'instancemethod'>: attribute lookup __builtin__.instancemethod failed

stolen from: https://bytes.com/topic/python/answers/552476-why-cant-you-pickle-instancemethods#edit2155350

how to use?
put this code before your multiprocessing call. yeah, just like that
"""
import copy_reg
import types


def _unpickle_method(func_name, obj, cls):
    for cls in cls.mro():
        try:
            func = cls.__dict__[func_name]
        except KeyError:
            pass
        else:
            break
    return func.__get__(obj, cls)


def _pickle_method(method):
    func_name = method.im_func.__name__
    obj = method.im_self
    cls = method.im_class
    return _unpickle_method, (func_name, obj, cls)


copy_reg.pickle(types.MethodType, _pickle_method, _unpickle_method)