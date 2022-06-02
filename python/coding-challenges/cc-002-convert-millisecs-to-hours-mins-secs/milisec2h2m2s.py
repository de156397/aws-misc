# This program converts milliseconds into hours, minutes and seconds
import time
seconds = int(round(time.time()))
hours = int(round(seconds/3600))
minute_seconds = int(round(seconds%3600))
minutes = int(round(minute_seconds/60))
seconds = int(round(minute_seconds%60))
print(hours,":",minutes,":",seconds)