#!python
import requests
import json
from pathlib import Path
import os
import re
import pandas as pd
from urllib.request import urlretrieve
#import wget
#import xml.etree.cElementTree as ET
#import xml.dom.minidom
#from xml.dom import minidom

home_dir = Path(os.environ["HOME"])
work_dir = Path(os.environ["WORKDIR"])
script_dir = Path(os.environ["SCRIPTDIR"])
target_dir = work_dir / 'uploaded'
try:
    os.mkdir(target_dir)
except OSError as error:
    print(error)

## Read ZenodoToken
filename = home_dir / '.ZenodoToken'
ZENODO_URL = "zenodo.org"
with open(filename,"r") as fo:
    ZENODO_TOKEN = fo.readline(60)


## list of published items in my profile
headers = {"Content-Type": "application/json"}
### query
ttl="Indicative distribution maps for Ecosystem Functional Groups - Level 3 of IUCN Global Ecosystem Typology"
qry="title:\"%s\"" % ttl
qsize=200
#qry="title:'distribution maps'"

r_list = requests.get('https://%s/api/deposit/depositions'  % ZENODO_URL,
                   params={'access_token': ZENODO_TOKEN, 
                           'q': qry, 'size': 120, 'page': 1,
                           'all_versions': True},
                   headers=headers)
r_list.status_code
len(r_list.json())


my_dict = [{'id': i['id'], 
            'created': i['created'],
            'doi': i['doi'], 
            'state': i['state'], 
            'version': i['metadata']['version'], 
            'title': i['title'],
            'files': i['files']} for i in r_list.json()]

df = pd.DataFrame(my_dict)
df = df.sort_values(by=['created'])
df = df.loc[df.title == ttl]
df[['doi','version','created']]



for index, row in df.iterrows():
    print(row["version"],row["id"], len(row['files']))
    version_dir = target_dir / row["version"]
    try:
        os.mkdir(version_dir)
    except OSError as error:
        print(error)
    for file in row["files"]:
        target_file = version_dir / file['filename']
        if os.path.isfile(target_file):
            print("{} already present\n".format(file['filename']))
        else:
            path, headers = urlretrieve(file['links']['download'].replace('draft/',''),
                                target_file)
            print("{} downloaded\n".format(file['filename']))
