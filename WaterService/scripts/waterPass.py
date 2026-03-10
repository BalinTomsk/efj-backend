
import requests
import time
import sys

def worker(interval, path):
    f = open(path, "r")
    lines = f.readlines()
    for line in lines:
        args=line.split('\t')
        if "call" not in args[0]:
            continue
        try:
            mli= args[1].strip()
            state =  args[2].strip()
            print("process: "+ mli + " : " + state)
            surl="http://fishfind.info/WebService/PushStation.aspx?mli=" + mli + "&state=" + state
            r = requests.get(surl)
            if r.status_code != 200:
                print("Failed to process station: " + r.text)
            time.sleep(interval)
        except ZeroDivisionError as err:
            print("Error: ", err)
    f.close()
    return


if __name__ == "__main__":
    worker(5, sys.argv[1])