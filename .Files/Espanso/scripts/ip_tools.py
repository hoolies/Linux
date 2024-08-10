import ipaddress
import subprocess

class IPTools:
    """This class takes an IP address with CIDR and returns a generate_dictionary
    Example: from ip_tools import IPTools
    ip_tools = IPTools("102.163.23.15/6")
    ip_tools.print_output()
    """

    def __init__(self) -> None:
        """Input: IP address and cidr notation example: 102.153.23.41/23.15
        Output: dictionary with the all the information"""
    
        command_list: list = 'xclip -o -sel clip'.split(' ')
        self.paste = str(subprocess.check_output(command_list).decode())
    
    def generate_dictionary(self) -> dict:
        network = ipaddress.IPv4Network(self.paste, strict=False)

        ip_address: str = str(self.paste.split('/')[0])
        subnet_mask: str = str(network.netmask)
        ip_range: list = [str(ip) for ip in network.hosts()]
        available_ips: int = int(len(ip_range))
        broadcast: str = str(network.broadcast_address)

        return {
            "Network": str(network),
            "IP Address": ip_address,
            "Range": f"{str(ip_range[0])} - {str(ip_range[-1])}",
            "Subnet Mask": subnet_mask,
            "Usable IPs": available_ips,
            "Broadcast": broadcast
        }
    
    def print_output(self) -> None:
        info: dict = self.generate_dictionary()
        dict_to_list: list = [f'\t"{k}":\t{v}' for k,v in info.items()]
        print(*dict_to_list, sep="\n")
        
def main() -> None:
    ip_tools = IPTools()
    ip_tools.print_output()

if __name__ == "__main__":
    main()
