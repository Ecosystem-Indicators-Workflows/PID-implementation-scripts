#! python
import requests
import json
from pathlib import Path
import glob, os
import sys
import xml.etree.cElementTree as ET


# declare paths
home_dir = Path(os.environ["HOME"])
xml_dir = Path(os.environ["XMLDIR"])
xport_dir = Path(os.environ["WORKDIR"])


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


longname=root.find("EFG/Name").text

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

json_object = json.dumps(main_deposition['metadata'], indent=4)

with open(xport_dir / "metadata-query.json", "w") as outfile:
    outfile.write(json_object)
exit()