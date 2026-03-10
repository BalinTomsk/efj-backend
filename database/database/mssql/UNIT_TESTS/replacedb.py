import os
import io
import sys
import uuid
import codecs
import configparser

settings = configparser.ConfigParser()
settings.read('config.ini')

infilename=settings.get('app','script')
outfilename='scriptdb.sql'
originaldb=settings.get('app','origindb')
newdbdb=str(uuid.uuid4())
newdbdb=newdbdb[:8]
print (newdbdb)

# -------------------   replace template database name with last created ----------------------

infile = codecs.open(infilename,'r')
outfile = codecs.open(outfilename, 'w')
for line in infile:
    fixed_line = line.replace(originaldb,newdbdb)
    outfile.write(fixed_line)
infile.close()
outfile.close()

# -------------------   save dbname to ini file                          ----------------------

inifile = open('dbname.ini', 'w')
inifile.write('dbname=' + newdbdb)
inifile.close()
