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


def get_node_id(node_name):
    """Get Node ID from node name"""
    query = """
        SELECT NodeID, Caption
        FROM Orion.Nodes
        WHERE Caption = @node_name
    """
    try:
        result = swis.query(query, node_name=node_name)
        if not result['results']:
            print(f"❌ No node found with name: {node_name}")
            sys.exit(1)
        node_id = result['results'][0]['NodeID']
        print(f"📍 Found node {node_name} with ID: {node_id}")
        return node_id
    except Exception as e:
        print(f"❌ Error looking up node: {str(e)}")
        sys.exit(1)


def process_node(node_id):
    """Process interfaces for a specific node"""
    # Query includes Unplugged field to check current state
    query = f"""
        SELECT InterfaceID, Caption, Status, InterfaceAlias, Unplugged 
        FROM Orion.NPM.Interfaces 
        WHERE NodeID={node_id}
    """
    interfaces = swis.query(query)
    
    for interface in interfaces['results']:
        int_status = interface['Status']
        int_caption = interface['Caption']
        int_alias = interface['InterfaceAlias']
        
        if int_status == 2:  # If interface is down
            int_id = interface['InterfaceID']
            uri = f"swis://SOLARWINDS_SERVER_IP:17778/Orion/Orion.Nodes/NodeID={node_id}/Interfaces/InterfaceID={int_id}"
            
            # Set Unplugged=1 instead of Status=10
            swis.update(uri, Unplugged=1)
            print(f"📡 Marking interface {int_caption} as unplugged")


def list_nodes(pattern=None):
    """List all nodes or nodes matching a pattern"""
    query = """
        SELECT NodeID, Caption
        FROM Orion.Nodes
        WHERE Caption LIKE @pattern
        ORDER BY Caption
    """
    try:
        pattern = f"%{pattern}%" if pattern else "%"
        result = swis.query(query, pattern=pattern)
        if not result['results']:
            print("No nodes found")
            return
        print("\nAvailable nodes:")
        for node in result['results']:
            print(f"  {node['Caption']} (ID: {node['NodeID']})")
    except Exception as e:
        print(f"❌ Error listing nodes: {str(e)}")


def main():
    parser = argparse.ArgumentParser(description='SolarWinds Interface Management Script')
    parser.add_argument('--node', help='Node name or ID to process')
    parser.add_argument('--test', action='store_true', help='Test connection to SolarWinds server')
    parser.add_argument('--list', nargs='?', const='', help='List all nodes or nodes matching a pattern')
    
    args = parser.parse_args()
    
    if args.test:
        test_connection()
        return

    if args.list is not None:
        list_nodes(args.list)
        return
    
    if args.node is None:
        print("Error: Please provide a node name/ID, use --test, or use --list")
        parser.print_help()
        sys.exit(1)
    
    # Try to convert node to ID, if it's not a number, treat it as a name
    try:
        node_id = int(args.node)
    except ValueError:
        node_id = get_node_id(args.node)
        
    process_node(node_id)


if __name__ == "__main__":
    main()