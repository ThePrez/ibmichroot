#!/bin/sh
#
# global
#

if [ -d /QOpenSys/usr/bin ]
then
  system_OS400=1
  # setup paths to IBM Open source binaries and libraries 
  # Notes: https://bitbucket.org/litmis/ibmichroot/issues/8/alternative-download-pkg_setupsh-on-linux
  PATH=/QOpenSys/usr/bin:/QOpenSys/usr/sbin:/opt/freeware/bin
  LIBPATH=/QOpenSys/usr/lib:/opt/freeware/lib
  export PATH
  export LIBPATH
  echo "**********************"
  echo "Live IBM i session (changes made)."
  echo "**********************"
  echo "PATH=$PATH"
  echo "LIBPATH=$LIBPATH"
else
  system_OS400=0
  echo "**********************"
  echo "Not IBM i, downloads only, other no action taken."
  echo "**********************"
fi

RPM_RTE="rpm.rte"
RPM_WGET="wget-1.9.1-1.aix5.1.ppc.rpm"
# oss4aix_fix_libiconv
#   na
# output
#   na
function package_fix_libiconv {
  name=$1
  case "$name" in
    *libiconv*)
      if (($system_OS400==1))
      then
        echo "fixing /opt/freeware/lib/libiconv.a ..."
        ar -x /QOpenSys/usr/lib/libiconv.a
        # Argh Matie, we be needin' to make a ugly baby to fool the IFS Kraken
        cp /opt/freeware/lib/libiconv.a /opt/freeware/lib/libiconv-lady-in-waiting.a
        ar -rv /opt/freeware/lib/libiconv-lady-in-waiting.a shr4.o
        ar -rv /opt/freeware/lib/libiconv-lady-in-waiting.a shr.o
        rm /opt/freeware/lib/libiconv.a
        cp /opt/freeware/lib/libiconv-lady-in-waiting.a /opt/freeware/lib/libiconv.a
      else
        echo "not IBM i, ignoring /opt/freeware/lib/libiconv.a ..."
      fi
    ;;
  esac
}
#
# wget RPM.lst
#
function package_download {
  name=$1
  base=$(basename $name)
  if [ -e $base ]
  then
    echo "message: $base - previously downloaded"
  else
    # need wget400, because newer versions not work
    # LIBPATH=/QOpenSys/usr/lib:/opt/freeware/lib
    if (($system_OS400==1))
    then
      if [ -f /opt/freeware/bin/wget400 ]
      then
        wget400 $name
      else
        cp /opt/freeware/bin/wget /opt/freeware/bin/wget400
        wget400 $name
      fi
    # download linux fine with any old wget
    else
      wget $name
    fi
  fi
}
#
# install RPM.lst
#
function package_install {
  name=$1
  base=$(basename $name)
  if (($system_OS400==1))
  then
    echo "install $base ..."
    rpm --ignoreos --ignorearch --nodeps --replacepkgs -hUv $base
  else
    echo "error: can not install $base, not running IBM i"
  fi
}
#
# remove RPM.lst
#
function remove_filetype_suffix {
  echo $1 | awk '{ gsub(/.ppc|.deps|.rpm|.aix5.1|.aix6.1|.aix7.1/,""); print }'
}
function package_remove {
  name=$1
  base=$(basename $name)
  if (($system_OS400==1))
  then
    mywild=$(remove_filetype_suffix $base)
    echo "remove query RPM package $mywild"
    words=$(rpm -qs $mywild)
    case "$words" in
      "")
        echo "alternative query RPM package $base"
        words=$(rpm -qlp $base)
      ;;
      *)
        rpm -e --nodeps $mywild
        rpm -e --justdb --nodeps $mywild
      ;;
    esac
    # force remove every file
    for myfile in $words
    do
      if test -d $myfile
      then
        echo "rm -R $myfile"
        rm -R $myfile
      fi
      if test -e $myfile
      then
        echo "rm $myfile"
        rm $myfile
      fi
    done
  else
    echo "error: can not remove $base, not running IBM i"
  fi
}
#
# read list action
#
function package_read_action {
  opr=$1
  pkg=$2
  action=""
  while read name; do
    case "$name" in
      "")
        # echo "empty"
      ;;
      *#*)
        # echo "comment"
      ;;
      ":file")
        action=$name
      ;;
      *:rpm*)
        action=$name
      ;;
      *)
        case "$action" in
          ":file")
            echo "Processing file: $name"
            package_read_action $opr $name
            action=":file"
          ;;
          ":rpm")
            case "$opr" in
              -w)
                package_download $name
              ;;
              -i)
                package_require_rpm
                package_install $name
                package_fix_libiconv $name
              ;;
              -a)
                package_require_rpm
                package_download $name
                package_install $name
                package_fix_libiconv $name
              ;;
              -k)
                package_require_rpm
                package_remove $name
              ;;
            esac
          ;;
        esac
      ;;
    esac
  done <$pkg
}
#
# setup RPM (standard)
#
function package_setup_rpm {
  cdhere=$(pwd)
  echo "setup $RPM_RTE ..."
  restore -xvqf $RPM_RTE
  cd $cdhere
  mkdir /QOpenSys/opt
  cp -R usr/opt/* /QOpenSys/opt/.
  rm -R usr
  ln -s /QOpenSys/opt /QOpenSys/var/opt
  ln -s /QOpenSys/opt /opt
  mkdir /var
  ln -s /QOpenSys/var/opt /var/opt
  ln -s /opt/freeware/bin/rpm /usr/bin/rpm
  cd /opt/freeware/lib
  ln -s libpopt.so.0.0.0 libpopt.so
  ln -s librpm.so.0.0.0 librpm.so
  ln -s librpmbuild.so.0.0.0 librpmbuild.so
  cd $cdhere
  echo "setup $RPM_WGET ..."
  rpm --ignoreos --ignorearch --nodeps --replacepkgs -hUv $RPM_WGET
  if [ -f /opt/freeware/bin/wget400 ]
  then
    wget400 --version
  else
    cp /opt/freeware/bin/wget /opt/freeware/bin/wget400
    wget400 --version
  fi
}

function package_require_rpm {
  if (($system_OS400==1)); then
    # rpm available?
    if test -e /usr/bin/rpm; then
      return 1
    fi
    # setup rpm
    package_setup_rpm
    # rpm available?
    if test -e /usr/bin/rpm; then
      return 1
    fi
    echo "Error: /usr/bin/rpm not found"
    exit
  else
    return 1
  fi
}
#
# main
#
opr="-a"
pkg=""
for arg in "$@"
{
  case "$arg" in
    -w)
      opr=$arg
    ;;
    -i)
      opr=$arg
    ;;
    -a)
      opr=$arg
    ;;
    -k)
      opr=$arg
    ;;
    fix)
      opr=$arg
    ;;
    *)
      pkg=$arg
    ;;
  esac
}
# error input check
case "$opr" in
  fix)
   # nothing
  ;;
  *)
    pkgok=$(echo $pkg | grep -c ".lst")
    if (($pkgok==0))
    then
      opr="error"
    fi
  ;;
esac
# run operation
case "$opr" in
  *-*)
    package_read_action $opr $pkg
  ;;
  fix)
    package_fix_libiconv "libiconv"
  ;;
  *)
    echo "./$(basename $0) [-w|-i|-a|-k] /path/pkg_*.lst"
    echo "   -a - wget and install rpm list (default)"
    echo "   -w - wget rpm list (no install)"
    echo "   -i - install rpm list (no wget)"
    echo "   -k - remove rpm list (destructive)"
    echo "   fix - fix perzl libiconv"
    echo "Example:"
    echo "  ./pkg_setup.sh pkg_gcc-4.6.2.lst"
  ;;
esac

