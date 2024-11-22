SolarWinds Interface Management Script
====================================

DESCRIPTION
-----------
This script interfaces with the SolarWinds API to manage network interface states. 
It uses environment variables for authentication and provides options for testing 
connectivity and processing specific nodes.

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

Process a Specific Node:
   python sw_unplugged_script.py --node 3007

ERROR HANDLING
-------------
The script will:
- Verify environment variables are set before attempting connection
- Provide clear error messages for missing parameters
- Report connection test results
- Exit with appropriate status codes

NOTES
-----
- The script requires proper SolarWinds API permissions
- Node IDs can be found in your SolarWinds console
- Connection tests perform a minimal query to verify connectivity
- Status code 2 represents interfaces that need processing