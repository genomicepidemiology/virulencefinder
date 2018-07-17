VirulenceFinder
===================

This project documents the VirulenceFinder service


Documentation
=============

The VirulenceFinder service contains one python script virulencefinder.py which is the script of the latest
version of the VirulenceFinder service. VirulenceFinder identifies viruelnce genes in total or partial sequenced
isolates of bacteria - at the moment only E. coli, Enterococcus, S. aureus and Listeria are available.


## Content of the repository
1. virulencefinder.py      - the program
2. test     	- test folder
3. README.md
4. Dockerfile   - dockerfile for building the virulencefinder docker container


## Installation

Setting up VirulenceFinder program
```bash
# Go to wanted location for virulencefinder
cd /path/to/some/dir
# Clone and enter the virulencefinder directory
git clone https://bitbucket.org/genomicepidemiology/virulencefinder.git
cd virulencefinder
```

Build Docker container
```bash
# Build container
docker build -t virulencefinder .
# Run test
docker run --rm -it \
       --entrypoint=/test/test.sh virulencefinder
```

#Download and install VirulenceFinder database

```bash
# Go to the directory where you want to store the virulencefinder database
cd /path/to/some/dir
# Clone database from git repository (develop branch)
git clone https://bitbucket.org/genomicepidemiology/virulencefinder_db.git
cd virulencefinder_db
VIRULENCE_DB=$(pwd)
# Install VirulenceFinder database with executable kma_index program
python3 INSTALL.py kma_index
```

If kma_index has no bin install please install kma_index from the kma repository:
https://bitbucket.org/genomicepidemiology/kma

## Usage

The program can be invoked with the -h option to get help and more information of the service.
Run Docker container:


```bash
# Run virulencefinder container
docker run --rm -it \
       -v $VIRULENCE_DB:/database \
       -v $(pwd):/workdir \
       virulencefinder -i [INPUTFILE] -o [OUTDIR] [-d] [-p] [-mp] [-l] [-t] [-tmp] [-x]
```

When running the docker file you must mount 2 directories: 
 1. virulencefinder_db (VirulenceFinder database) downloaded from bitbucket
 2. An output/input folder from where the input file can be reached and an output files can be saved. 
Here we mount the current working directory (using $pwd) and use this as the output directory, 
the input file should be reachable from this directory as well. The path to the infile and outfile
directories should be relative to the monuted current working directory.


`-i INPUTFILE	input file (fasta or fastq) relative to pwd, up to 2 files`

`-o OUTDIR	output directory relative to pwd`

`-d DATABASE    set a specific database`

`-p DATABASE_PATH    set path to database, default is /database`

`-mp METHOD_PATH    set path to method (blast or kma)`

`-l MIN_COV    set threshold for minimum coverage`

`-t THRESHOLD set threshold for mininum blast identity`

`-tmp    temporary directory for storage of the results from the external software`

`-x    extended output`

## Web-server

A webserver implementing the methods is available at the [CGE website](http://www.genomicepidemiology.org/) and can be found here:
https://cge.cbs.dtu.dk/services/VirulenceFinder/

Citation
=======

When using the method please cite:

Real-time whole-genome sequencing for routine typing, surveillance, and outbreak detection of verotoxigenic Escherichia coli.
Joensen KG, Scheutz F, Lund O, Hasman H, Kaas RS, Nielsen EM, Aarestrup FM.
J. Clin. Micobiol. 2014. 52(5): 1501-1510.
[Epub ahead of print]


License
=======

Copyright (c) 2014, Ole Lund, Technical University of Denmark
All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
