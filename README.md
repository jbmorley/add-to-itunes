add-to-itunes
=============

Objective-C command line utility to fetch relevant metadata and artwork for video files and add them to iTunes.

Usage
-----

```
usage: add-to-itunes: [-h] [--delete] filename [filename ...]

Fetch the metadata for a video media file (movie or show).

positional arguments:
  filename    filename of the media to be searched for

optional arguments:
  -h, --help    show this message and exit
  --delete, -d    delete the original file
```

Building
--------

From the root of the project:

```
git submodule update --init --recursive
./scripts/build.sh
```
