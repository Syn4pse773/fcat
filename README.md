# fcat

A simple utility similar to cat, written in FASM (Flat Assembler) for x86_64 Linux.

## Requirements

- Flat Assembler (fasm)
- Linux x86_64

## Compilation

To compile the source code:

```bash
fasm fcat.asm fcat
chmod +x fcat
```

## Usage

```bash
./fcat <filename>
```

If no filename argument is provided, the program outputs an error message and exits with code 1.
