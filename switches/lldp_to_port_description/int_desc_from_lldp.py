import paramiko
import time
import re
import sys
from abc import ABC, abstractmethod
from typing import List, Tuple, Dict

class SwitchAdapter(ABC):
    def __init__(self, channel):
        self.channel = channel
    
    def clear_buffer(self):
        while self.channel.recv_ready():
            self.channel.recv(4096)
            
    def execute_command(self, command: str, wait_time: float = 1) -> str:
        self.clear_buffer()
        self.channel.send(command + "\n")
        time.sleep(wait_time)
        
        output = ""
        time_waited = 0
        max_wait = 3
        
        while time_waited < max_wait:
            if self.channel.recv_ready():
                chunk = self.channel.recv(4096).decode('utf-8')
                output += chunk
                if not self.channel.recv_ready():
                    break
            else:
                time.sleep(0.1)
                time_waited += 0.1
        
        return output
    
    @abstractmethod
    def set_terminal_length(self) -> str:
        pass
    
    @abstractmethod
    def get_lldp_info(self) -> str:
        pass
    
    @abstractmethod
    def parse_lldp_info(self, lldp_output: str) -> Tuple[List[Dict], List[Dict]]:
        pass
    
    @abstractmethod
    def get_interface_description(self, interface: str) -> str:
        pass
    
    @abstractmethod
    def enter_config_mode(self) -> List[str]:
        pass
    
    @abstractmethod
    def generate_interface_commands(self, interface: str, description: str) -> List[str]:
        pass

class DellV6Adapter(SwitchAdapter):
    SKIP_DESCRIPTIONS = ["(none)"]
    
    def set_terminal_length(self) -> str:
        return self.execute_command("terminal length 0", wait_time=2)
    
    def get_lldp_info(self) -> str:
        return self.execute_command("show lldp remote-device all", wait_time=2)
    
    def parse_lldp_info(self, lldp_output: str) -> Tuple[List[Dict], List[Dict]]:
        lines = lldp_output.split('\n')
        parsed_info = []
        skipped_interfaces = []
        
        for line in lines:
            if line.strip():
                parts = re.split(r'\s+', line.strip())
                if len(parts) >= 5 and parts[0].startswith(('Gi', 'Te')):
                    system_name = ' '.join(parts[4:])
                    if system_name in self.SKIP_DESCRIPTIONS:
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
    
    def get_interface_description(self, interface: str) -> str:
        output = self.execute_command(
            f"show running-config interface {interface} | include description",
            wait_time=2
        )
        
        for line in output.splitlines():
            if 'description' in line:
                match = re.search(r'description\s+"([^"]+)"', line)
                if match:
                    return match.group(1)
        return ""
    
    def enter_config_mode(self) -> List[str]:
        return ["conf"]
    
    def generate_interface_commands(self, interface: str, description: str) -> List[str]:
        return [
            f"interface {interface}",
            f'description "{description}"',
            "exit"
        ]

def create_adapter(switch_type: str, channel) -> SwitchAdapter:
    adapters = {
        "dellv6": DellV6Adapter
    }
    
    adapter_class = adapters.get(switch_type.lower())
    if not adapter_class:
        raise ValueError(f"Unsupported switch type: {switch_type}")
        
    return adapter_class(channel)

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

def generate_description_commands(adapter, parsed_info):
    commands = adapter.enter_config_mode()
    updates_needed = False
    
    print("\nChecking current interface descriptions...")
    for info in parsed_info:
        current_description = adapter.get_interface_description(info['interface'])
        new_description = info['system_name']
        
        print(f"\nChecking {info['interface']}:")
        print(f"  Current description: '{current_description}'")
        print(f"  Proposed description: '{new_description}'")
        
        if current_description != new_description:
            commands.extend(adapter.generate_interface_commands(info['interface'], new_description))
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

def apply_changes(adapter, commands):
    for command in commands:
        adapter.execute_command(command)
    print("\n\n\nProcess complete, we've deliberately not written changes to startup-config as another safety procedure")
    time.sleep(2)

def main(username, password, switch_ip, switch_type="dellv6"):
    print("Script started.")
    ssh, channel = connect_to_switch(switch_ip, username, password)
    
    try:
        adapter = create_adapter(switch_type, channel)
        adapter.set_terminal_length()
        
        lldp_output = adapter.get_lldp_info()
        if not lldp_output.strip():
            print("No LLDP information retrieved. Exiting.")
            return

        parsed_info, skipped_interfaces = adapter.parse_lldp_info(lldp_output)

        if skipped_interfaces:
            print("\nSkipped Interfaces (matched skip list):")
            for info in skipped_interfaces:
                print(f"Interface: {info['interface']}, System Name: {info['system_name']}")

        print("\nParsed LLDP Info:")
        for info in parsed_info:
            print(f"Interface: {info['interface']}, System Name: {info['system_name']}")

        commands, updates_needed = generate_description_commands(adapter, parsed_info)
        
        if not updates_needed:
            print("\nNo description updates needed. All interfaces are already properly configured.")
            return
            
        print("\nCommands to be applied:")
        for command in commands:
            print(command)

        countdown_timer(10)
        apply_changes(adapter, commands)

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