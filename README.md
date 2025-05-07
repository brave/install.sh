# Brave Browser installer for Linux

It is designed to be piped directly into `sh`

See https://brave.com/linux for manual installation instructions

## Design goals

1. Succeed in installing the browser everywhere it can work, keeping external dependencies to a minimum
2. Automatically detect and/or fix problems that users may encounter (i.e. help with #1 and reduce the need to contact Support)
3. Reduce friction and unnecessary confirmation prompts, and support non-interactive installation
4. While achieving the above goals, keep complexity to a minimum so that the script can be inspected easily by users
