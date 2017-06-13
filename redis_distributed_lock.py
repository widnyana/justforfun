# -*- coding: utf-8 -*-
"""
Usage:

>>> lock = redis_lock.distributed_lock('SOME_LOCK_NAME', 'functionname_performing_the_lock')
>>> if lock is not False:
>>>     with open(A_PATH_TO_FILE, 'a') as f:
>>>         f.write(json.dumps(SOME_DATA))
>>>     redis_lock.distributed_unlock('SOME_LOCK_NAME', 'functionname_performing_the_lock')

WTFPL 2017 - wid [at] widnyana.web.id
"""

import os
import platform
import collections
import redis

#: set config here.
RedisConfig = collections.namedtuple('RedisConfig', 'REDIS_HOST REDIS_PORT REDIS_DBNUMBER')
config = RedisConfig(REDIS_HOST='localhost', REDIS_PORT=6379, REDIS_DBNUMBER=0)

def connect_redis():
    conn = redis.StrictRedis(host=config.REDIS_HOST, port=config.REDIS_PORT, db=config.REDIS_DBNUMBER)

    return conn


def distributed_lock(lockname, locker, ttl=120):
    """create lock marker on redis

    :param lockname: lock identifier
    :param locker: who perform lock?
    :param ttl: key time-to-live
    :return: False or lock-value
    """
    nodename = platform.node()
    pid = os.getpid()
    expected_value = "{node}-{locker}:{pid}".format(
        node=nodename,
        locker=locker,
        pid=pid
    )

    c = connect_redis()

    result = c.get(lockname)
    if result is not None:
        if result == expected_value:
            return expected_value
    else:
        c.set(lockname, expected_value)
        c.expire(lockname, ttl)
        return expected_value

    return False

def distributed_unlock(lockname, locker):
    """remove lock marker

    :param lockname: lockname
    :param locker: who perform the lock
    :return: status
    """
    nodename = platform.node()
    pid = os.getpid()
    expected_value = "{node}-{locker}:{pid}".format(
        node=nodename,
        locker=locker,
        pid=pid
    )

    c = connect_redis()
    result = c.get(lockname)

    if result is None:
        #: already unlocked or ttl has passed
        return True

    else:
        #: hanya locker yang bisa mengunlock
        if result == expected_value:
            status = c.delete(lockname)
            return status

    return False
