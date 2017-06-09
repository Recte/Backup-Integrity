# Backup-Integrity
Collection of scripts for Bash and Powershell to confirm data integrety between backup locations

The goal of the scripts in this repository is to create a easy and fast way to index and compare several filelocations. I felt the need to do so, since I got the feeling that not all my backup locations where in sync. This repository will contain BASH and Powershell scripts.

## BASH Scripts

### Backup_Index_Agent.bsh
This bash script is tested on de latest Synology Build, Ubuntu 17 and Raspbian Jessie and uses 'Backup_Index_Agent.conf' for its configuration.

The script indexes files by a relative path and generates sha256 filehashes, so they can be:
* compared with the CSV's of other locations;
* you can search for duplicate files, based on their filehash

## Powershell Scripts
...
