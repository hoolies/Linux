import subprocess
from re import sub


class SymbolRemoval:

    def __init__(self) -> None:
        """Get the content of the clipboard"""
        command_list: list = 'xclip -o -sel clip'.split(' ')
        self.paste = str(subprocess.check_output(command_list).decode())

    def remove_symbols(self) -> str:
        return sub(r'\W', '', self.paste)


def main() -> None:
    sr = SymbolRemoval()
    sr.remove_symbols()

if __name__ == "__main__":
    main()
