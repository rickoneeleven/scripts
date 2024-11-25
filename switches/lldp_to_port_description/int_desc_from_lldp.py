from abc import ABC, abstractmethod
import paramiko
import time
import re
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
                output += self.channel.recv(4096).decode('utf-8')
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