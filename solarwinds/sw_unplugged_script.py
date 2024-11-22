import requests
from orionsdk import SwisClient
from pprint import pprint
import json

requests.packages.urllib3.disable_warnings()

with open("LOCAL/PATH/TO/creds.json") as credentials:
    creds = json.load(credentials)

server = 'SOLARWINDS_SERVER_IP'
username = creds['sw_api_user']
password = creds['sw_api_pass']

swis = SwisClient(server, username, password)


def main():

    node_choice = 3007
    query = f"SELECT InterfaceID, Caption, Status, InterfaceAlias FROM Orion.NPM.Interfaces WHERE NodeID={node_choice}"
    interfaces = swis.query(query)
    for interface in interfaces['results']:
        int_status = interface['Status']
        int_caption = interface['Caption']
        int_alias = interface['InterfaceAlias']
        if int_status == 2:
            int_id = interface['InterfaceID']
            uri = f"swis://SOLARWINDS_SERVER_IP:17778/Orion/Orion.Nodes/NodeID={node_choice}/Interfaces/" \
                f"InterfaceID={int_id}"
            swis.update(uri, Status=10)
            pprint(f"Changing interface {int_caption}")


if __name__ == "__main__":
    main()