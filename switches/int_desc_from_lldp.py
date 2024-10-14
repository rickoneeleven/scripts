import paramiko
import time
import re
import sys

def connect_to_switch(switch_ip, username, password, timeout=2):
    print(f"Attempting to connect to {switch_ip}...")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh.connect(switch_ip, username=username, password=password, timeout=timeout)
        print("Successfully connected to the switch.")
        channel = ssh.invoke_shell()
        return ssh, channel
    except Exception as e:
        print(f"Failed to connect to the switch: {str(e)}")
        sys.exit(1)

def execute_command(channel, command, wait_time=1):
    print(f"Executing: {command}")
    channel.send(command + "\n")
    time.sleep(wait_time)
    output = ""
    while channel.recv_ready():
        output += channel.recv(4096).decode('utf-8')
    print("Output:", output)
    return output

def get_lldp_info(channel):
    print("Executing 'show lldp remote-device all' command...")
    return execute_command(channel, "show lldp remote-device all", wait_time=2)

def parse_lldp_info(lldp_output):
    print("Parsing LLDP output...")
    lines = lldp_output.split('\n')
    parsed_info = []
    for line in lines:
        if line.strip():
            parts = re.split(r'\s+', line.strip())
            if len(parts) >= 5 and parts[0].startswith(('Gi', 'Te')):
                parsed_info.append({
                    'interface': parts[0],
                    'system_name': ' '.join(parts[4:])
                })
    print(f"Parsed {len(parsed_info)} LLDP entries.")
    return parsed_info

def generate_description_commands(parsed_info):
    print("Generating description update commands...")
    commands = ["conf"]
    for info in parsed_info:
        commands.append(f"interface {info['interface']}")
        commands.append(f"description {info['system_name']}")
        commands.append("exit")
    commands.append("end")
    commands.append("write")
    commands.append("y")
    return commands

def apply_changes(channel, commands):
    print("Applying changes to the switch...")
    try:
        for command in commands:
            execute_command(channel, command)
        print("All commands executed.")
        print("Waiting 10 seconds for any tasks to complete...")
        time.sleep(111)
        return True
    except Exception as e:
        print(f"Failed to apply changes: {str(e)}")
        return False

def main(username, password, switch_ip):
    print("Script started.")
    ssh, channel = connect_to_switch(switch_ip, username, password)
    try:
        lldp_output = get_lldp_info(channel)
        if not lldp_output.strip():
            print("No LLDP information retrieved. Exiting.")
            return

        parsed_info = parse_lldp_info(lldp_output)

        print("\nParsed LLDP Info:")
        for info in parsed_info:
            print(f"Interface: {info['interface']}, System Name: {info['system_name']}")

        commands = generate_description_commands(parsed_info)
        
        print("\nCommands to update interface descriptions:")
        print("\n".join(commands))

        user_input = input("\nWould you like me to apply these changes? y/n (default n): ").strip().lower()
        
        if user_input == 'y':
            apply_changes(channel, commands)
            print("Please check the switch configuration to confirm the changes.")
        else:
            print("Changes were not applied.")

    except Exception as e:
        print(f"An unexpected error occurred: {str(e)}")
    finally:
        print("Closing SSH connection...")
        ssh.close()
        print("Script finished.")

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python3 script.py <username> <password> <switch_ip>")
        sys.exit(1)
    
    username = sys.argv[1]
    password = sys.argv[2]
    switch_ip = sys.argv[3]
    
    main(username, password, switch_ip)