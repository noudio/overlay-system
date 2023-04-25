#!/bin/bash
# Runs a command in docker with the live root mounted as an overlay
# args: user cwd --ro <mounts> --rw <mounts> -- <command +args>

# pre: /mount-magic/root-org  has the root ('/') mounted recursive bind rw mounted
#      (note that a simple docker run -v /:/mount-magic/root-org does it)
# -------------------------------------------------------------------------
set -e
# -------------------------------------------------------------------------
verbose=
myName="$(basename $0)"
# A unique name, identifyable in persistent volumes
#myUniqueName="ovlsys-208d5058-2be3-4532-a061-d47b62f490c4"
myUniqueName="ovl"
theUser="$1"
theCwd="$2"
shift 2 || true

# =========================================================
mntSrc=
mntDst=
# -----------------------------------
function rootrelative-path () {
  # $1 = <possible relative path>
  echo $(chroot /mount-magic/root-org bash -c "cd \"$theCwd\" ;realpath \"$1\"" | sed -e 's/^\///g')
}
# -------------------------------
function parse-mount-src-dst () {
  # $1 = 'mount-src:mount-dst'

  # mount-src must exist and must be (at least) readable
  mntSrc=$(rootrelative-path $(echo "$1" | awk -F: '{print $1}'))
  if [ '!' -r "/mount-magic/root-org/$mntSrc" ]; then
     echo "$myName: mount source: '/$mntSrc' is not readable"
     exit 1
  fi

  # if mount-dst is empty it will be the source
  mntDst=$(echo "$1" | awk -F: '{print $2}')
  if [ -n "$mntDst" ]; then
      mntDst=$(rootrelative-path "$mntDst")
  else
      mntDst=$mntSrc
  fi
}
# -------------------------------
function verbose-function () {
   if [ -n "$verbose" ]; then
      echo "$myName: doing:" "$@"
   fi
   "$@"
}
# -------------------------------
function verbose-info () {
   if [ -n "$verbose" ]; then
      echo "$myName:" "$@"
   fi
}
# -------------------------------
function exit-trap()
{
   rc=$?
   [ $rc -ne 0 ] && echo "$myName: exiting with code: $rc" 1>&2
   exit $rc
}
trap exit-trap EXIT

# -------------
#scan arguments

scanMode='cmd' # 'ro' , 'rw'
listCommand=()
listRoSrc=()
listRoDst=()
listRwSrc=()
listRwDst=()

while [ -n "$1" ]; do

   case "$1" in
      --)
        scanMode='cmd'
        shift
        continue
        ;;
      -ro | --mount-ro)
        scanMode='ro'
        shift
        continue
        ;;
      -rw | --mount-rw)
        scanMode='rw'
        shift
        continue
        ;;
      -v | --verbose)
        verbose=1
        shift
        continue
        ;;
   esac
   case "$scanMode" in
      cmd)
        listCommand+=("$1")
        shift
        ;;
      ro)
        parse-mount-src-dst "$1"
        #echo "ro: /$mntSrc -> /$mntDst"
        listRoSrc+=("$mntSrc")
        listRoDst+=("$mntDst")
        shift
        ;;
      rw)
        parse-mount-src-dst "$1"
        #echo "rw: /$mntSrc -> /$mntDst"
        listRwSrc+=("$mntSrc")
        listRwDst+=("$mntDst")
        shift
        ;;
   esac
done

# =================================================================
# lsblk | grep disk # (to find out real disks)
# lsblk --list --output NAME,TYPE | awk '{if($2 == "disk") {print $1}}'
# lsblk | grep '/mount/magic' # (to find out which parts are mounted)

listOverlay=($(lsblk --list --output NAME,TYPE,MOUNTPOINT | \
               awk '{if ($3~/^\/mount-magic\/root-org/ && ($2 == "part" || $2 == "lvm")) {print $3}}' | \
               sort))

# =================================================================
# add handy rw mounts
#   run is needed for various symlinks inside it
listRwSrc+=(dev sys proc tmp run)
listRwDst+=(dev sys proc tmp run)

# =================================================================
# print it out (debug)
verbose-info "command: ${#listCommand[@]}: ${listCommand[*]}"
verbose-info "overlay: ${#listOverlay[@]}: ${listOverlay[*]}"
verbose-info "ro src:  ${#listRoSrc[@]}: ${listRoSrc[*]}"
verbose-info "ro dst:  ${#listRoDst[@]}: ${listRoDst[*]}"
verbose-info "rw src:  ${#listRwSrc[@]}: ${listRwSrc[*]}"
verbose-info "rw dst:  ${#listRwDst[@]}: ${listRwDst[*]}"

# ================================================================
# mount /dev from the root-org for the container, otherwise it cannot
# get a pseudo tty for the chroot
verbose-function mount --rbind /mount-magic/root-org/dev /dev
# ================================================================
# prepare directories and mountpoints

# /mount-magic/overlay can be mounted with a persistent docker volume
# in case it is not mounted, we mount or own temp file system here

if ! mountpoint /mount-magic/overlay > /dev/null 2>&1
then
    # the tmpfs (or any other none docker filesys) is crucial
    # all disk changes will end up here
    mkdir -p /mount-magic/overlay
    verbose-function mount -t tmpfs tmpfs /mount-magic/overlay
else
    verbose-info "using persistent storage"
fi

# =================================================================
# 2) Make all overlay mounts
mkdir -p /mount-magic/root-merged
nrMounts=$((${#listOverlay[@]}))
for (( i=0; i<$nrMounts; i++ )); do
   overlayLower=$(echo ${listOverlay[$i]})
   overlayName=$(echo $overlayLower | sed -e 's/^\/mount-magic\/root-org/root/g')
   #if [ "$overlayName" = "/mount-magic/root-org" ]; then
   #   overlayName="root"
   #else
   #fi
   overlayUpper="/mount-magic/overlay/$overlayName/$myUniqueName-upper"
   overlayWork="/mount-magic/overlay/$overlayName/$myUniqueName-work"
   overlayMerged="/mount-magic/overlay-merged/$overlayName/merged"

   # Make the overlay mount
   mkdir -p $overlayUpper $overlayWork $overlayMerged
   if verbose-function mount -t overlay -o lowerdir=$overlayLower,upperdir=$overlayUpper,workdir=$overlayWork overlay $overlayMerged
   then
       overlayFinalMerge=$(echo $overlayLower | sed -e 's/^\/mount-magic\/root-org/\/mount-magic\/root-merged/g')
       verbose-function mount --rbind $overlayMerged  $overlayFinalMerge
   else
       echo "$myName: WARNING: $overlayName could not be mounted."
   fi
done

# --------------------------------------------------------
# 3) bind mount all readonly sources on top of root-merged
#    for example to replace system directories with an alternative
nrMounts=$((${#listRoSrc[@]}))
for (( i=0; i<$nrMounts; i++ )); do
   verbose-function mount --rbind -o ro "/mount-magic/root-org/${listRoSrc[$i]}" "/mount-magic/root-merged/${listRoDst[$i]}"
done

# ---------------------------------------------------------
# 4) bind mount all readwrite sources on top of root-merged
#    this is the only way to get something out of this overlay-system

nrMounts=$((${#listRwSrc[@]}))
for (( i=0; i<$nrMounts; i++ )); do
   verbose-function mount --rbind "/mount-magic/root-org/${listRwSrc[$i]}" "/mount-magic/root-merged/${listRwDst[$i]}"
done

# =================================================================
# 5) perform the supplied command, (if any)
interActive=
theCommand=${listCommand[*]}
if [ -z "$theCommand" ]; then
    #empty command, run interactive
    theCommand="echo -e \"\nYou are in a overlay container!\n\"; bash -i"
    interActive=1
fi

verbose-function chroot /mount-magic/root-merged su -l -P $theUser bash -c "cd \"$theCwd\"; $theCommand"
rc=$?
[ -n "$interActive" ] && echo "$myName: done"
exit $rc
