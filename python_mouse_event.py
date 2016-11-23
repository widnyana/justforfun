import os
from evdev import InputDevice, categorize, ecodes
from select import select
dev = InputDevice("/dev/input/event4")

while True:
    r,w,x = select([dev], [], [])
    for event in dev.read():
        if event.type == ecodes.EV_KEY:
            print categorize(event)
            
