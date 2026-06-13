# fcat

A `cat` clone written in pure x86-64 assembly (FASM) for Linux. No libc, no runtime — direct syscalls only.

## Features

- Concatenates multiple files to standard output
- Reads from standard input when given `-` or no file arguments
- Buffered I/O (4 KiB read/write buffers) with a zero-copy fast path when no formatting flags are set
- Per-file error reporting (`fcat: <file>: <reason>`) without aborting the remaining files
- `EINTR` and short-write handling on all read/write syscalls

## Requirements

- [FASM](https://flatassembler.net/) (Flat Assembler)
- Linux on x86-64

## Build

```bash
fasm fcat.asm fcat
chmod +x fcat
```

## Install

Copy the binary to a directory on your `PATH`:

```bash
install -Dm755 fcat ~/.local/bin/fcat
```

## Usage

```bash
fcat [-nEs] [file...]
```

Flags may be grouped (e.g. `-nE`):

| Flag | Description                         |
|------|-------------------------------------|
| `-n` | Number all output lines             |
| `-E` | Append `$` to the end of each line  |
| `-s` | Squeeze repeated blank lines        |

`--` ends flag parsing; every argument after it is treated as a file name.
A lone `-`, or no file arguments, reads from standard input.

## Exit status

| Code | Meaning                                  |
|------|------------------------------------------|
| `0`  | Success                                  |
| `1`  | A file could not be read, or invalid flag |

## License

[MIT](LICENSE)
