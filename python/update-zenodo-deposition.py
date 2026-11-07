#! python
import requests
import json
from pathlib import Path
import glob, os
import sys
import xml.etree.cElementTree as ET
import datetime

## define functions

autaff = { ## currently only five direct contributors to the maps
        "DA Keith" : {'affiliation': 'University of New South Wales', 'name': 'Keith, David A.', 'orcid': '0000-0002-7627-4150'},
        "S Gorta" : {'affiliation': 'University of New South Wales', 'name': 'Gorta, Simon B.Z.', 'orcid': '0000-0002-7753-556X'},
        "JR Ferrer-Paris" : {'affiliation': 'University of New South Wales', 'name': 'Ferrer-Paris, Jose R.', 'orcid': '0000-0002-9554-3395'},
        "P Pliscoff" : {'affiliation': 'Pontifica Universidad Católica de Chile', 'name': 'Pliscoff, Patricio','orcid': '0000-0002-5971-8880'},
        "NJ Murray" : {'affiliation': 'James Cook University', 'name': 'Murray, Nicholas J.', 'orcid': '0000-0002-4008-3053'}
    }

# declare paths
home_dir = Path(os.environ["HOME"])
xml_dir = Path(os.environ["XMLDIR"])
xport_dir = Path(os.environ["ZIPDIR"])
## get recordid

# ask for EFG
if len(sys.argv) == 2:
    EFG = sys.argv[1]
else:
    EFG = input("Choose Ecosystem Functional Group (EFG) :~~~>")

# read xml file with detailed version information queried from database
qrystr = "%s/%s*" % (xml_dir,EFG.replace('.','_'))
file_names=glob.glob(qrystr)
xml_file = file_names[0]
tree = ET.parse(xml_file)
root = tree.getroot()


## Read ZenodoToken
ZENODO_URL = "zenodo.org"
with open(home_dir / '.ZenodoToken',"r") as fo:
    ZENODO_TOKEN = fo.readline(60)

## Today is...
today = datetime.date.today()

authors=list()
for aut in root.findall("EFG/Contributors/map-contributor"):
    authors.append(autaff[aut.text])

longname=root.find("EFG/Name").text
shortname=root.find("EFG/Short-name").text
mapcode = root.find("EFG/Map").attrib['code']
mapver = root.find("EFG/Map").attrib['version']
pflver = root.findall("EFG")[0].attrib['version']

## query from zenodo
headers = {"Content-Type": "application/json"}
### query
qry="title:\"%s\"" % longname
qsize=10
r_list = requests.get('https://%s/api/deposit/depositions'  % ZENODO_URL,
                   params={'access_token': ZENODO_TOKEN, 'q': qry, 'size': 120, 'page': 1},
                   headers=headers)
res=r_list.json()

if len(res)==1:
    main_deposition=res[0]
else:
    print("no match!")



rid = main_deposition['conceptrecid']
target_dir = xport_dir / rid 

newdata={'metadata':main_deposition['metadata']}
newdata['metadata']['creators'] = authors
newdata['metadata']['version']="{} {}".format(mapcode, mapver)
newdata['metadata']['publication_date']=str(today)

## check if new files match existing files, and ask for confirmation of update
file_actions=dict()

for fl in main_deposition['files']:
    file_actions[fl['filename']]='d'

for i in glob.glob("%s/*" % target_dir):
    fl=os.path.basename(i)
    if fl in file_actions.keys():
        file_actions[fl]='r'
    else:
        file_actions[fl]='u'

inputstr = """File {} marked as ({}), confim with enter or: 
(d)elete, (r)eplace, (u)pload or (i)gnore or (A)bort :~~~>"""
for k in file_actions:
    newaction = input(inputstr.format(k,file_actions[k]))
    if newaction =="A":
        print("No actions taken, bye!")
        exit()
    elif newaction != "":
        file_actions[k]=newaction


r_add = requests.post(main_deposition['links']['newversion'],
                  params={'access_token': ZENODO_TOKEN}, data={},
                  headers=headers)

print("New version: {} {}".format(r_add.status_code, r_add.reason)) 

# Code: 201 Created or 403 if already open
if r_add.status_code==201:
    new_deposition = r_add.json()
else:
    new_deposition = main_deposition

#new_deposition_url=r_new.json()['links']['latest_draft']
## important to avoid error with the doi...
newdata['metadata']['doi'] = new_deposition['metadata']['prereserve_doi']['doi']


## this will update the metadata to the new version of the deposition_id
r_mod = requests.put(new_deposition['links']['latest_draft'],
                  params={'access_token': ZENODO_TOKEN}, data=json.dumps(newdata),
                  headers=headers)

print("Update metadata {} {}".format(r_mod.status_code, r_mod.reason)) 

## now we need to replace files with newer versions
## query files and delete if marked as (d) or (r)

bucket_url = new_deposition["links"]["bucket"]

if bucket_url == 'https://zenodo.org/api/files/':
    print("file bucket url is missing, file actions need to be done via browser, aborting")
    exit()
else:
    print("Bucket at {}".format(bucket_url))


fls = requests.get(new_deposition['links']['files'],
                  params={'access_token': ZENODO_TOKEN},
                  headers=headers)

print("Files: {} {}".format(fls.status_code, fls.reason)) 

if fls.status_code in (200,):
    archivos = fls.json()
    for archivo in archivos:
        print(archivo['filename'])
        if file_actions[archivo['filename']] in ('d','r'):
            dfls = requests.delete(archivo['links']['self'],
                                params={'access_token': ZENODO_TOKEN},
                                headers=headers)
            print("Request delete: {} {}".format(dfls.status_code, dfls.reason)) 
else:
    print("Problem here, no files found")



## now we get the list of data to add to the deposition
## first two large zip files with all the raster and all the vector maps, each with a README and xml documentation of map methods and references


for file_name in glob.glob("%s/*" % target_dir):
    archivo=os.path.basename(file_name)
    if archivo in file_actions.keys():
        if file_actions[archivo] in ('r','u'):
            with open(file_name, "rb") as opened_file:
                ufls = requests.put('%s/%s' % (bucket_url,archivo),
                                 data=opened_file,
                                 params={'access_token': ZENODO_TOKEN})
            print("Request upload {}: {} {}".format(archivo, ufls.status_code, ufls.reason)) 

## When we are ready to publish we can do this, but it is better to do this directly on the site
#r = requests.post('https://sandbox.zenodo.org/api/deposit/depositions/%s/actions/publish' % deposition_id,
#                  params={'access_token': ACCESS_TOKEN} )
# r.status_code

exit()
