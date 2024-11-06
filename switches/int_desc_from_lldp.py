import paramiko
import time
import re
import sys

# List of system names to skip when updating descriptions
SKIP_DESCRIPTIONS = ["(none)", ]  # Add more with commas, e.g. ["(none)", "unknown", "test"]

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

def clear_buffer(channel):
    while channel.recv_ready():
        channel.recv(4096)

def execute_command(channel, command, wait_time=1):
    clear_buffer(channel)  # Clear any leftover data
    channel.send(command + "\n")
    time.sleep(wait_time)
    
    # Initial read
    output = ""
    time_waited = 0
    max_wait = 3  # Maximum seconds to wait for output
    
    while time_waited < max_wait:
        if channel.recv_ready():
            chunk = channel.recv(4096).decode('utf-8')
            output += chunk
            if not channel.recv_ready():
                break
        else:
            time.sleep(0.1)
            time_waited += 0.1
    
    return output

def set_terminal_length(channel):
    return execute_command(channel, "terminal length 0", wait_time=2)

def get_lldp_info(channel):
    return execute_command(channel, "show lldp remote-device all", wait_time=2)

def get_interface_description(channel, interface):
    # Clear buffer and wait a bit longer for response
    output = execute_command(channel, f"show running-config interface {interface} | include description", wait_time=2)
    
    # Look for the description line in the output
    for line in output.splitlines():
        if 'description' in line:
            match = re.search(r'description\s+"([^"]+)"', line)
            if match:
                return match.group(1)
    return ""

def parse_lldp_info(lldp_output):
    lines = lldp_output.split('\n')
    parsed_info = []
    skipped_interfaces = []
    
    for line in lines:
        if line.strip():
            parts = re.split(r'\s+', line.strip())
            if len(parts) >= 5 and parts[0].startswith(('Gi', 'Te')):
                system_name = ' '.join(parts[4:])
                if system_name in SKIP_DESCRIPTIONS:
                    skipped_interfaces.append({
                        'interface': parts[0],
                        'system_name': system_name
                    })
                    continue
                parsed_info.append({
                    'interface': parts[0],
                    'system_name': system_name
                })
    return parsed_info, skipped_interfaces

def generate_description_commands(channel, parsed_info):
    commands = ["conf"]
    updates_needed = False
    
    print("\nChecking current interface descriptions...")
    for info in parsed_info:
        current_description = get_interface_description(channel, info['interface'])
        new_description = info['system_name']
        
        print(f"\nChecking {info['interface']}:")
        print(f"  Current description: '{current_description}'")
        print(f"  Proposed description: '{new_description}'")
        
        if current_description != new_description:
            commands.append(f"interface {info['interface']}")
            commands.append(f'description "{new_description}"')
            commands.append("exit")
            updates_needed = True
            print("  -> Update needed")
        else:
            print("  -> No update needed (descriptions match)")
    
    commands.append("end")
    return commands, updates_needed

def countdown_timer(seconds):
    print("\nReviewing changes before application...")
    for i in range(seconds, 0, -1):
        sys.stdout.write(f"\rProceeding with changes in {i} seconds... Press Ctrl+C to abort")
        sys.stdout.flush()
        time.sleep(1)
    print("\nApplying changes...")

def apply_changes(channel, commands):
    for command in commands:
        execute_command(channel, command)
    print()
    print()
    print()
    print("Process complete, we've deliberately not written changes to startup-config as another safety procedure")
    time.sleep(2)

def main(username, password, switch_ip):
    print("Script started.")
    ssh, channel = connect_to_switch(switch_ip, username, password)
    try:
        set_terminal_length(channel)
        lldp_output = get_lldp_info(channel)
        if not lldp_output.strip():
            print("No LLDP information retrieved. Exiting.")
            return

        parsed_info, skipped_interfaces = parse_lldp_info(lldp_output)

        if skipped_interfaces:
            print("\nSkipped Interfaces (matched skip list):")
            for info in skipped_interfaces:
                print(f"Interface: {info['interface']}, System Name: {info['system_name']}")

        print("\nParsed LLDP Info:")
        for info in parsed_info:
            print(f"Interface: {info['interface']}, System Name: {info['system_name']}")

        commands, updates_needed = generate_description_commands(channel, parsed_info)
        
        if not updates_needed:
            print("\nNo description updates needed. All interfaces are already properly configured.")
            return
            
        print("\nCommands to be applied:")
        for command in commands:
            print(command)

        countdown_timer(10)
        apply_changes(channel, commands)

    except KeyboardInterrupt:
        print("\nOperation cancelled by user.")
    except Exception as e:
        print(f"An unexpected error occurred: {str(e)}")
    finally:
        print("Closing SSH connection...")
        ssh.close()

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python3 script.py <username> <password> <switch_ip>")
        sys.exit(1)
    
    username = sys.argv[1]
    password = sys.argv[2]
    switch_ip = sys.argv[3]
    
    main(username, password, switch_ip)