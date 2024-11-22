import requests
from orionsdk import SwisClient
from pprint import pprint
import os
import sys
import argparse

requests.packages.urllib3.disable_warnings()

# Get credentials from environment variables
server = os.environ.get('SOLARWINDS_SERVER_IP')
username = os.environ.get('SOLARWINDS_API_USER')
password = os.environ.get('SOLARWINDS_API_PASS')

# Check if environment variables are set
if not all([server, username, password]):
    raise EnvironmentError(
        "Missing required environment variables. Please ensure SOLARWINDS_SERVER_IP, "
        "SOLARWINDS_API_USER, and SOLARWINDS_API_PASS are set."
    )

swis = SwisClient(server, username, password)


def test_connection():
    """Test connection to SolarWinds server"""
    try:
        # Simple query to test connection
        swis.query("SELECT TOP 1 NodeID FROM Orion.Nodes")
        print("✅ Successfully connected to SolarWinds server")
        return True
    except Exception as e:
        print(f"❌ Failed to connect to SolarWinds server: {str(e)}")
        return False


def process_node(node_id):
    """Process interfaces for a specific node"""
    query = f"SELECT InterfaceID, Caption, Status, InterfaceAlias FROM Orion.NPM.Interfaces WHERE NodeID={node_id}"
    interfaces = swis.query(query)
    for interface in interfaces['results']:
        int_status = interface['Status']
        int_caption = interface['Caption']
        int_alias = interface['InterfaceAlias']
        if int_status == 2:
            int_id = interface['InterfaceID']
            uri = f"swis://SOLARWINDS_SERVER_IP:17778/Orion/Orion.Nodes/NodeID={node_id}/Interfaces/" \
                f"InterfaceID={int_id}"
            swis.update(uri, Status=10)
            pprint(f"Changing interface {int_caption}")


def main():
    parser = argparse.ArgumentParser(description='SolarWinds Interface Management Script')
    parser.add_argument('--node', type=int, help='Node ID to process')
    parser.add_argument('--test', action='store_true', help='Test connection to SolarWinds server')
    
    args = parser.parse_args()
    
    if args.test:
        test_connection()
        return
    
    if args.node is None:
        print("Error: Please provide a node ID or use --test")
        parser.print_help()
        sys.exit(1)
        
    process_node(args.node)


if __name__ == "__main__":
    main()