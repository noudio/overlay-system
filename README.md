
Usage:
```
overlay-system [-v|--verbose] \
               [-p|--persistent <name>] \
               [-ro src[:dst] [src[:dst] ...]] \
               [-rw src[:dst] [src[:dst] ...]] \
               [-- cmd [args ...]]

   Runs command 'cmd' within a 'transparent docker container'
   Within this container, all system disks are overlayed.
   All changes to the disks from the outside are seen from within.
   But all changes to the disks from within, are not actually done
   to the real disks. Except for some directories that can be
   mounted 'rw'. When no command given, runs a bash shell interactively.
   This is ideal for playing 'what-if' scenarios when installing linux 
   system packages etc. Or investigating what changes are done onto the
   system, by certain operations
  

   Options:
     -v  show what is done
     -p  use persistent volume <name> for all changes to the system
     -ro 'mnt-specs' Read only mount something alternative on top of an existing directory.
     -rw 'mnt-specs' Is the only way to get something out of the overlay-system.
     --  Stop commandline parsing, all arguments are the command line

     'mnt-specs' are of the form src[:dst]
        src - Source directory within /
        dst - Destination directory. it must pre-exist. When destination
              is empty, the same as 'src' is used. for example -rw /home/noud makes
              /home/noud writable
```
Example:
```  
   # run 'ls' on a bind-mounted /opt/torch directory
   #          only /home/noudio is 'really' writable...
   $ mkdir -p fake-torch; touch fake-torch/fake-torch.txt
   $ overlay-system -ro fake-torch:/opt/torch -rw /home/noudio \
                    -- "ls /opt/torch > /home/noudio/test.txt"
   $ cat /home/noud/test.txt
   fake-torch.txt
```
To build the docker image overlay-mount:
```  
   ./overlay-system-docker-build.sh
```
