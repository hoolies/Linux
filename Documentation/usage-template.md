# coreutils usage wording

Copy this shape. Replace `PROG`, the one-line description, options, and operand names. Keep the quoted sentences exactly.

```sh
usage() {
    cat <<EOF
Usage: $PROGNAME [OPTION]... [FILE]...
One-line description of what the program does.

Mandatory arguments to long options are mandatory for short options too.

  -a, --all             description of this option
  -h, --help            display this help and exit
EOF
}
```

Unrecognized option (stderr, exit 2):

```
$PROGNAME: unrecognized option $arg
Try '$PROGNAME --help' for more information.
```

`PROGNAME` is `${0##*/}`.

Optional operands in the Usage line use `[NAME]`. Repeatable tokens use `...`. Mutually exclusive forms get extra `Usage:` lines, same as coreutils.

Do not invent `--version` or extra GNU boilerplate unless the user asked.
