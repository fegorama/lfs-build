# Linux From Scratch Automation Script Building

Automation script for creating a GNU/Linux distribution based on an initial system following the book "Linux From Scratch" by Gerard Beekmans.

## Sintaxis

Usage: lfs-build <buildtools|buildbase|builddist> -p <installation_path> -u <user> [-v <version>] [-h]

    buildtools    Build temporary tools
    buildbase     Build the base system to compile LFS
    builddist     Build the LFS base system
    -p            Path where LFS will be installed
    -u            User for the initial installation (first phase) - it is recommended to use lfs
    -v            Version of Linux From Scratch (default: $LFS_VERSION)
    -h            Show this help

Run this command as root.


## Examples

    ./lfs-build.sh buildtools -p /mnt/lfs -u lfsuser
    ./lfs-build.sh buildbase
    ./lfs-build.sh builddist
    ./lfs-build.sh -h

