#!/bin/bash

set -e
set -x

NAME_DISTRIBUTION="FegorOS"
LOG_FILE="blfs-build.log"

# Config Bash Shell for BLFS
create_profile() {
    cat > /etc/profile << "EOF"
# Begin /etc/profile
# Written for Beyond Linux From Scratch
# by James Robertson <jameswrobertson@earthlink.net>
# modifications by Dagmar d'Surreal <rivyqntzne@pbzpnfg.arg>

# System wide environment variables and startup programs.

# System wide aliases and functions should go in /etc/bashrc.  Personal
# environment variables and startup programs should go into
# ~/.bash_profile.  Personal aliases and functions should go into
# ~/.bashrc.

# Functions to help us manage paths.  Second argument is the name of the
# path variable to be modified (default: PATH)
pathremove () {
        local IFS=':'
        local NEWPATH
        local DIR
        local PATHVARIABLE=${2:-PATH}
        for DIR in ${!PATHVARIABLE} ; do
                if [ "$DIR" != "$1" ] ; then
                  NEWPATH=${NEWPATH:+$NEWPATH:}$DIR
                fi
        done
        export $PATHVARIABLE="$NEWPATH"
}

pathprepend () {
        pathremove $1 $2
        local PATHVARIABLE=${2:-PATH}
        export $PATHVARIABLE="$1${!PATHVARIABLE:+:${!PATHVARIABLE}}"
}

pathappend () {
        pathremove $1 $2
        local PATHVARIABLE=${2:-PATH}
        export $PATHVARIABLE="${!PATHVARIABLE:+${!PATHVARIABLE}:}$1"
}

export -f pathremove pathprepend pathappend

# Set the initial path
export PATH=/usr/bin

# Attempt to provide backward compatibility with LFS earlier than 11
if [ ! -L /bin ]; then
        pathappend /bin
fi

if [ $EUID -eq 0 ] ; then
        pathappend /usr/sbin
        if [ ! -L /sbin ]; then
                pathappend /sbin
        fi
        unset HISTFILE
fi

# Set up some environment variables.
export HISTSIZE=1000
export HISTIGNORE="&:[bf]g:exit"

# Set some defaults for graphical systems
export XDG_DATA_DIRS=${XDG_DATA_DIRS:-/usr/share}
export XDG_CONFIG_DIRS=${XDG_CONFIG_DIRS:-/etc/xdg}
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp/xdg-$USER}

# Set up a red prompt for root and a green one for users.
NORMAL="\[\e[0m\]"
RED="\[\e[1;31m\]"
GREEN="\[\e[1;32m\]"
if [[ $EUID == 0 ]] ; then
  PS1="$RED\u [ $NORMAL\w$RED ]# $NORMAL"
else
  PS1="$GREEN\u [ $NORMAL\w$GREEN ]\$ $NORMAL"
fi

for script in /etc/profile.d/*.sh ; do
        if [ -r $script ] ; then
                . $script
        fi
done

unset script RED GREEN NORMAL

# End /etc/profile
EOF

    install --directory --mode=0755 --owner=root --group=root /etc/profile.d

    cat > /etc/profile.d/bash_completion.sh << "EOF"
# Begin /etc/profile.d/bash_completion.sh
# Import bash completion scripts

# If the bash-completion package is installed, use its configuration instead
if [ -f /usr/share/bash-completion/bash_completion ]; then

  # Check for interactive bash and that we haven't already been sourced.
  if [ -n "${BASH_VERSION-}" -a -n "${PS1-}" -a -z "${BASH_COMPLETION_VERSINFO-}" ]; then

    # Check for recent enough version of bash.
    if [ ${BASH_VERSINFO[0]} -gt 4 ] || \
       [ ${BASH_VERSINFO[0]} -eq 4 -a ${BASH_VERSINFO[1]} -ge 1 ]; then
       [ -r "${XDG_CONFIG_HOME:-$HOME/.config}/bash_completion" ] && \
            . "${XDG_CONFIG_HOME:-$HOME/.config}/bash_completion"
       if shopt -q progcomp && [ -r /usr/share/bash-completion/bash_completion ]; then
          # Source completion code.
          . /usr/share/bash-completion/bash_completion
       fi
    fi
  fi

else

  # bash-completions are not installed, use only bash completion directory
  if shopt -q progcomp; then
    for script in /etc/bash_completion.d/* ; do
      if [ -r $script ] ; then
        . $script
      fi
    done
  fi
fi

# End /etc/profile.d/bash_completion.sh
EOF

    install --directory --mode=0755 --owner=root --group=root /etc/bash_completion.d

    cat > /etc/profile.d/dircolors.sh << "EOF"
# Setup for /bin/ls and /bin/grep to support color, the alias is in /etc/bashrc.
if [ -f "/etc/dircolors" ] ; then
        eval $(dircolors -b /etc/dircolors)
fi

if [ -f "$HOME/.dircolors" ] ; then
        eval $(dircolors -b $HOME/.dircolors)
fi

alias ls='ls --color=auto'
alias grep='grep --color=auto'
EOF

    cat > /etc/profile.d/extrapaths.sh << "EOF"
if [ -d /usr/local/lib/pkgconfig ] ; then
        pathappend /usr/local/lib/pkgconfig PKG_CONFIG_PATH
fi
if [ -d /usr/local/bin ]; then
        pathprepend /usr/local/bin
fi
if [ -d /usr/local/sbin -a $EUID -eq 0 ]; then
        pathprepend /usr/local/sbin
fi

if [ -d /usr/local/share ]; then
        pathprepend /usr/local/share XDG_DATA_DIRS
fi

# Set some defaults before other applications add to these paths.
pathappend /usr/share/info INFOPATH
EOF

    cat > /etc/profile.d/readline.sh << "EOF"
# Set up the INPUTRC environment variable.
if [ -z "$INPUTRC" -a ! -f "$HOME/.inputrc" ] ; then
        INPUTRC=/etc/inputrc
fi
export INPUTRC
EOF

    cat > /etc/profile.d/umask.sh << "EOF"
# By default, the umask should be set.
if [ "$(id -gn)" = "$(id -un)" -a $EUID -gt 99 ] ; then
  umask 002
else
  umask 022
fi
EOF

cat > /etc/profile.d/i18n.sh << "EOF"
# Set up i18n variables
for i in $(locale); do
  unset ${i%=*}
done

if [[ "$TERM" = linux ]]; then
  export LANG=C.UTF-8
else
  export LANG=es_ES.utf8
fi
EOF
}

inicialization_values() {
    cat > /etc/bashrc << "EOF"
# Begin /etc/bashrc
# Written for Beyond Linux From Scratch
# by James Robertson <jameswrobertson@earthlink.net>
# updated by Bruce Dubbs <bdubbs@linuxfromscratch.org>

# System wide aliases and functions.

# System wide environment variables and startup programs should go into
# /etc/profile.  Personal environment variables and startup programs
# should go into ~/.bash_profile.  Personal aliases and functions should
# go into ~/.bashrc

# Provides colored /bin/ls and /bin/grep commands.  Used in conjunction
# with code in /etc/profile.

alias ls='ls --color=auto'
alias grep='grep --color=auto'

# Provides prompt for non-login shells, specifically shells started
# in the X environment. [Review the LFS archive thread titled
# PS1 Environment Variable for a great case study behind this script
# addendum.]

NORMAL="\[\e[0m\]"
RED="\[\e[1;31m\]"
GREEN="\[\e[1;32m\]"
if [[ $EUID == 0 ]] ; then
  PS1="$RED\u [ $NORMAL\w$RED ]# $NORMAL"
else
  PS1="$GREEN\u [ $NORMAL\w$GREEN ]\$ $NORMAL"
fi

unset RED GREEN NORMAL

# End /etc/bashrc
EOF
}

vim_config() {
mkdir -pv /etc/skel
    cat > /etc/skel/.vimrc << "EOF"
" Begin .vimrc

set columns=80
set wrapmargin=8
set ruler

" End .vimrc
EOF

cp -v /etc/skel/.vimrc /root/.vimrc
}

issue_config() {
    cat > /etc/issue << "EOF"
FegorOS - Forensic Examination and Governance Operating Resource %s %s (%s)
Kernel \r on an \m
EOF

    cat > /etc/issue.net << "EOF"
FegorOS - Forensic Examination and Governance Operating Resource %s %s (%s)
Kernel \r on an \m
EOF
}

number_random_generation() {
  cd /sources
  tar xvf blfs-bootscripts-20240416.tar.xz && cd ./blfs-bootscripts-20240416
  make install-random
}

install_openssh() {
  cd /sources
  tar xvf openssh-9.8p1.tar.gz && cd ./openssh-9.8p1

  install -v -g sys -m700 -d /var/lib/sshd
  groupadd -g 50 sshd        
  useradd  -c 'sshd PrivSep' \
          -d /var/lib/sshd  \
          -g sshd           \
          -s /bin/false     \
          -u 50 sshd

  ./configure --prefix=/usr                            \
              --sysconfdir=/etc/ssh                    \
              --with-privsep-path=/var/lib/sshd        \
              --with-default-path=/usr/bin             \
              --with-superuser-path=/usr/sbin:/usr/bin \
              --with-pid-dir=/run
  make 
  # make -j1 tests
  make install

  install -v -m755    contrib/ssh-copy-id /usr/bin     &&

  install -v -m644    contrib/ssh-copy-id.1 \
                      /usr/share/man/man1              &&
  install -v -m755 -d /usr/share/doc/openssh-9.8p1     &&
  install -v -m644    INSTALL LICENCE OVERVIEW README* \
                      /usr/share/doc/openssh-9.8p1

  # Config daemon
  cd /sources/blfs-bootscripts-20240416
  make install-sshd

  # Configuring OpenSSH
  # TODO: Create a function to configure OpenSSH
}

install_sudo() {
  cd /sources
  tar xvf sudo-1.9.15p5.tar.gz && cd ./sudo-1.9.15p5

  ./configure --prefix=/usr              \
              --libexecdir=/usr/lib      \
              --with-secure-path         \
              --with-env-editor          \
              --docdir=/usr/share/doc/sudo-1.9.15p5 \
              --with-passprompt="[sudo] password for %p: " &&
  make
  make install

  # Config sudo
  cat > /etc/sudoers.d/00-sudo << "EOF"
Defaults secure_path="/usr/sbin:/usr/bin"
%wheel ALL=(ALL) ALL
EOF

  # TODO: If PAM is installed, install the pam configuration
}

# Basic security configuration

basic_security() {
  install_openssh
  install_sudo
}

install_wget() {
  cd /sources
  tar xvf wget-1.24.5.tar.gz && cd ./wget-1.24.5

  ./configure --prefix=/usr      \
              --sysconfdir=/etc  \
              --with-ssl=openssl && make
  make install
}

# Basic network configuration

basic_network() {
  install_wget
}

# File system configuration

install_efivar() {
  cd /sources
  tar xvf efivar-39.tar.gz && cd ./efivar-39

  make 
  sudo make install LIBDIR=/usr/lib
}

install_efibootmgr() {
  cd /sources
  tar xvf efibootmgr-18.tar.gz && cd ./efibootmgr-18

  make EFIDIR=LFS EFI_LOADER=grubx64.efi
  sudo make install EFIDIR=${NAME_DISTRIBUTION}
}

install_grub() {
  cd /sources
  tar xvf grub-2.12.tar.xz && cd ./grub-2.12

  sudo mkdir -pv /usr/share/fonts/unifont 
  sudo gunzip -c ../unifont-15.1.05.pcf.gz | sudo tee /usr/share/fonts/unifont/unifont.pcf > /dev/null

  echo depends bli part_gpt > grub-core/extra_deps.lst

  ./configure --prefix=/usr        \
              --sysconfdir=/etc    \
              --disable-efiemu     \
              --enable-grub-mkfont \
              --with-platform=efi  \
              --target=x86_64      \
              --disable-werror     &&
  unset TARGET_CC &&
  make

  # If you've skip the LFS GRUB package, as the root user...
  sudo make install
  sudo mv -v /etc/bash_completion.d/grub /usr/share/bash-completion/completions

  # If you've not skip LFS GRUB package, as the root user, only install the components not installed from the LFS GRUB package instead...
  #sudo make DESTDIR=$PWD/dest install
  #sudo cp -av dest/usr/lib/grub/x86_64-efi -T /usr/lib/grub/x86_64-efi
  #sudo cp -av dest/usr/share/grub/*.{pf2,h}   /usr/share/grub
  #sudo cp -av dest/usr/bin/grub-mkfont        /usr/bin

  # If the optional dependencies are installed, also install the grub-mount program
  #cp -av dest/usr/bin/grub-mount /usr/bin
}

file_systems_configuration() {
  # TODO: Uncomment in the final version
  # Only for 64-bit systems, Don't install on 32-bit systems
  #install_efivar
  install_efibootmgr
  install_grub
}

create_user() {
  echo "Creating user fegor"
  groupadd forensics
  useradd -m -g forensics -s /bin/bash fegor
  usermod -aG wheel fegor
  passwd fegor
  chown -R fegor:forensics /sources/
}

install_mandoc() {
  cd /sources
  tar xvf mandoc-1.14.6.tar.gz && cd ./mandoc-1.14.6

  ./configure && make mandoc

  sudo install -vm755 mandoc   /usr/bin &&
  sudo install -vm644 mandoc.1 /usr/share/man/man1
}

install_popt() {
  cd /sources
  tar xvf popt-1.19.tar.gz && cd ./popt-1.19

  ./configure --prefix=/usr --disable-static &&
  make

  # If Doxygen-1.12.0 is installed, install the API documentation
  #sed -i 's@\./@src/@' Doxyfile &&
  #doxygen

  sudo make install

  # If you built the API documentation, install it
  #sudo install -v -m755 -d /usr/share/doc/popt-1.19 &&
  #sudo install -v -m644 doxygen/html/* /usr/share/doc/popt-1.19
}

install_utils() {
  echo "Installing utils"
  # TODO: uncomment in the final version
  #install_mandoc
  #install_popt
}

continue_installation_banner() {
  echo "For continue the installation, please restar our machine "
  echo "with: 'exit' and 'shutdown -r now', select new distribution "
  echo "partition and connect via SSH to the server: 'ssh fegor@<ip>' "
  echo "and run the command: '/blfs-build.sh continue'" 
}

main () {
  if [ "$1" == "continue" ]; then
    install_utils
    file_systems_configuration
  else
    # TODO: uncomment in the final version
    #create_profile
    #inicialization_values
    #source /user_profile.sh
    #vim_config
    #issue_config
    #number_random_generation
    
    #basic_security
    #basic_network
    #create_user
    continue_installation_banner
  fi
}

main "$1" | tee $LOG_FILE
