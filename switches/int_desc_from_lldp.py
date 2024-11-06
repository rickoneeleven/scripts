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

def execute_command(channel, command, wait_time=1):
    channel.send(command + "\n")
    time.sleep(wait_time)
    output = ""
    while channel.recv_ready():
        output += channel.recv(4096).decode('utf-8')
    print(output)
    return output

def set_terminal_length(channel):
    return execute_command(channel, "terminal length 0", wait_time=1)

def get_lldp_info(channel):
    return execute_command(channel, "show lldp remote-device all", wait_time=2)

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

def generate_description_commands(parsed_info):
    commands = ["conf"]
    for info in parsed_info:
        commands.append(f"interface {info['interface']}")
        commands.append(f'description "{info["system_name"]}"')
        commands.append("exit")
    commands.append("end")
    return commands

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

        print("\nParsed LLDP Info (will be updated):")
        for info in parsed_info:
            print(f"Interface: {info['interface']}, System Name: {info['system_name']}")

        commands = generate_description_commands(parsed_info)
        
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