import subprocess
from re import sub

class MarkDownTable:
    
    def __init__(self) -> None:
        """This function takes whatever is on the clipboard and returns it."""

        # Transforms the command to a list
        command_list: list = 'xclip -o -sel clip'.split(' ')

        # Decodes the byte output of the above command
        command = str(subprocess.check_output(command_list).decode())

        # Save the output to a list
        self.paste: list =  command.splitlines(True)

    def table_manipulation(self) -> str:
        """Make the copy spreadsheet to markdown table"""
        
        # The first row is the header
        header: str = sub(r'\s+', " | ", self.paste[0].strip())

        # Number of columns
        second_row: str = '-|' * len(self.paste[0].split('\t'))

        # body
        body: str = str([ sub(r'\s+', " | ", self.paste[i + 1].strip()).join("\n") for i, _ in enumerate(self.paste) ])

        return header + second_row + body

def main():
    mdtable = MarkDownTable()
    print(mdtable.table_manipulation())

if __name__ == "__main__":
    main()
