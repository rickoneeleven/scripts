SolarWinds Interface Management Script
====================================

DESCRIPTION
-----------
This script interfaces with the SolarWinds API to manage network interface states. 
It uses environment variables for authentication and provides options for testing 
connectivity and processing specific nodes. It can now handle both node names and IDs,
and properly sets interfaces as unpluggable.

PREREQUISITES
------------
- Python 3.6+
- orionsdk package
- requests package

INSTALLATION
-----------
1. Install required packages:
   pip install orionsdk requests

2. Set up environment variables in your ~/.bashrc:
   export SOLARWINDS_SERVER_IP='your_server_ip'
   export SOLARWINDS_API_USER='your_username'
   export SOLARWINDS_API_PASS='your_password'

3. Source your updated .bashrc:
   source ~/.bashrc

USAGE
-----
Test Connection:
   python sw_unplugged_script.py --test

List All Nodes:
   python sw_unplugged_script.py --list

List Nodes Matching Pattern:
   python sw_unplugged_script.py --list "EDGE"

Process by Node Name:
   python sw_unplugged_script.py --node RCP-SPI-EDGE10-A1

Process by Node ID:
   python sw_unplugged_script.py --node 3007

ERROR HANDLING
-------------
The script will:
- Verify environment variables are set before attempting connection
- Provide clear error messages for missing parameters
- Report connection test results
- Exit with appropriate status codes
- Validate node names and IDs before processing

NOTES
-----
- The script requires proper SolarWinds API permissions
- Node IDs can be found using the --list option
- Connection tests perform a minimal query to verify connectivity
- Status code 2 represents interfaces that need processing
- Interfaces are marked as Unpluggable=1 to properly handle down state