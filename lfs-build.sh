#!/bin/bash

# Linux From Scratch Automation Script
# Fegor's Creation Distribution for Linux

set -e
#set -x

# Global variables
INSTALL_PATH="/lfs"
LFS_USER="lfs"
LFS_VERSION="12.2"  # Cambia según la versión de LFS
LOG_FILE="lfs-build.log"
ACTION=""

# Función para mostrar ayuda
usage() {
    echo "Uso: $0 <buildtools|buildbase|builddist> -p <path_instalacion> -u <usuario> [-v <version>] [-h]"
    echo "  buildtools    Construir herramientas temporales"
    echo "  buildbase     Construir el sistema base para compilar LFS"
    echo "  builddist     Construir el sistema base LFS"
    echo "  -p            Path donde se instalará LFS"
    echo "  -u            Usuario para la instalación inicial (primera fase) - se recomienda usar lfs"
    echo "  -v            Versión de Linux From Scratch (por defecto: $LFS_VERSION)"
    echo "  -h            Mostrar esta ayuda"
    echo ""
    echo "Ejecutar este comando como root."
    exit 1
}

# Función para comprobar si se es root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Este script debe ejecutarse como root."
        exit 1
    fi
}

# Función para inicializar variables
initialize() {
    echo "Inicializando variables..."
    export LFS=$INSTALL_PATH
    mkdir -pv $LFS/{sources,tools}
    chmod -v a+wt $LFS/sources
}

# Función para validar dependencias
check_dependencies() {
    echo "Comprobando dependencias..."
    ./version-check.sh
}

# Función para descargar paquetes
download_sources() {
    set +e
    echo "Descargando fuentes..."
    wget --continue --no-clobber --input-file=./wget-list-sysv --continue --directory-prefix=$LFS/sources
    cp ./md5sums $LFS/sources
    pushd $LFS/sources
        md5sum -c md5sums
    popd
    set -e
}

# Función para configurar el entorno de construcción
prepare_environment() {
    echo "Preparando el entorno de construcción..."
    mkdir -pv $LFS/{etc,var} $LFS/usr/{bin,lib,sbin}

    for i in bin lib sbin; do
        if [ ! -L $LFS/$i ]; then
            ln -sv usr/$i $LFS/$i
        fi
    done

    case $(uname -m) in
        x86_64) mkdir -pv $LFS/lib64 ;;
    esac

    echo "Creando usuario $LFS_USER..."
    if ! getent group lfs > /dev/null; then
        groupadd lfs || true
    fi    

    if ! id -u $LFS_USER > /dev/null 2>&1; then
        useradd -s /bin/bash -g lfs -m -k /dev/null $LFS_USER
        passwd $LFS_USER
    fi

    chown -v lfs $LFS/{usr{,/*},lib,var,etc,bin,sbin,tools}
    case $(uname -m) in
        x86_64) chown -v lfs $LFS/lib64 ;;
    esac

    su - $LFS_USER <<EOF
cat > ~/.bash_profile << EOF1
exec env -i HOME=/home/$LFS_USER TERM=$TERM PS1='\u:\w\$ ' /bin/bash
EOF1
EOF

    su - $LFS_USER << EOF
echo "Creando fichero bashrc para $LFS_USER..."
cat > ~/.bashrc << EOF1
set +h
umask 022
LFS=$LFS
LC_ALL=POSIX
LFS_TGT=$(uname -m)-lfs-linux-gnu
PATH=/usr/bin
if [ ! -L /bin ]; then PATH=/bin:$PATH; fi
PATH=$LFS/tools/bin:$PATH
CONFIG_SITE=$LFS/usr/share/config.site
export LFS LC_ALL LFS_TGT PATH CONFIG_SITE
EOF1
EOF
}

# Función para construir herramientas temporales
build_temporary_tools() {
    echo "Construyendo herramientas temporales..."
    temp_binutils_pass1
    temp_gcc_pass1
    temp_linux_api_headers
    temp_gclib
    temp_libstdcxx
    temp_m4
    temp_ncurses
    temp_bash
    temp_coreutils
    temp_diffutils
    temp_file
    temp_findutils
    temp_gawk
    temp_grep
    temp_gzip
    temp_make
    temp_patch
    temp_sed
    temp_tar
    temp_xz
    temp_binutils_pass2
    temp_gcc_pass2
   
}

temp_binutils_pass1() {
    su - $LFS_USER << 'EOF'
source ~/.bashrc  
cd $LFS/sources
tar -xf binutils-2.43.1.tar.xz && cd binutils-2.43.1
mkdir -pv build && cd build
../configure --prefix=$LFS/tools \
        --with-sysroot=$LFS \
        --target=$LFS_TGT   \
        --disable-nls       \
        --enable-gprofng=no \
        --disable-werror    \
        --enable-new-dtags  \
        --enable-default-hash-style=gnu
make && make install
EOF
}

temp_gcc_pass1() {
    su - $LFS_USER << 'EOF'
source ~/.bashrc
cd $LFS/sources
tar -xf gcc-14.2.0.tar.xz && cd gcc-14.2.0
tar -xf ../mpfr-4.2.1.tar.xz && mv -v mpfr-4.2.1 mpfr
mv -v mpfr-4.2.1 mpfr 
tar -xf ../gmp-6.3.0.tar.xz && mv -v gmp-6.3.0 gmp
mv -v gmp-6.3.0 gmp
tar -xf ../mpc-1.3.1.tar.gz && mv -v mpc-1.3.1 mpc
mv -v mpc-1.3.1 mpc

case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
 ;;
esac

mkdir -pv build && cd build
../configure                  \
    --target=$LFS_TGT         \
    --prefix=$LFS/tools       \
    --with-glibc-version=2.40 \
    --with-sysroot=$LFS       \
    --with-newlib             \
    --without-headers         \
    --enable-default-pie      \
    --enable-default-ssp      \
    --disable-nls             \
    --disable-shared          \
    --disable-multilib        \
    --disable-threads         \
    --disable-libatomic       \
    --disable-libgomp         \
    --disable-libquadmath     \
    --disable-libssp          \
    --disable-libvtv          \
    --disable-libstdcxx       \
    --enable-languages=c,c++
make && make install
cd ..
cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
  `dirname $($LFS_TGT-gcc -print-libgcc-file-name)`/include/limits.h
EOF
}

temp_linux_api_headers() {
    su -l - $LFS_USER << 'EOF'
source ~/.bashrc
cd $LFS/sources
tar -xf linux-6.10.5.tar.xz && cd linux-6.10.5
make mrproper
make headers
find usr/include -name '.*' -delete
cp -rv usr/include $LFS/usr
EOF
}

temp_gclib() {
    su -l - $LFS_USER << 'EOF'
source ~/.bashrc
cd $LFS/sources
tar -xf glibc-2.40.tar.xz && cd glibc-2.40
case $(uname -m) in
    i?86)   ln -sfv ld-linux.so.2 $LFS/lib/ld-lsb.so.3
    ;;
    x86_64) ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64
            ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64/ld-lsb-x86-64.so.3
    ;;
esac
patch -Np1 -i ../glibc-2.40-fhs-1.patch
mkdir -v build && cd build
echo "rootsbindir=/usr/sbin" > configparms
../configure                             \
      --prefix=/usr                      \
      --host=$LFS_TGT                    \
      --build=$(../scripts/config.guess) \
      --enable-kernel=4.19               \
      --with-headers=$LFS/usr/include    \
      --disable-nscd                     \
      libc_cv_slibdir=/usr/lib
make && make DESTDIR=$LFS install
sed '/RTLDLIST=/s@/usr@@g' -i $LFS/usr/bin/ldd
echo 'int main(){}' | $LFS_TGT-gcc -xc -
readelf -l a.out | grep ld-linux
rm -v a.out
EOF
}

temp_libstdcxx() {
    su -l - $LFS_USER << 'EOF'
source ~/.bashrc
cd $LFS/sources
cd gcc-14.2.0
mv build build-pass-1
mkdir -pv build && cd build
../libstdc++-v3/configure           \
    --host=$LFS_TGT                 \
    --build=$(../config.guess)      \
    --prefix=/usr                   \
    --disable-multilib              \
    --disable-nls                   \
    --disable-libstdcxx-pch         \
    --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/14.2.0
make && make DESTDIR=$LFS install
rm -v $LFS/usr/lib/lib{stdc++{,exp,fs},supc++}.la
EOF
}

temp_m4() {
    su - $LFS_USER << 'EOF'
source ~/.bashrc
cd $LFS/sources
tar -xf m4-1.4.19.tar.xz && cd m4-1.4.19
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make && make DESTDIR=$LFS install
EOF
}

temp_ncurses() {
    su - $LFS_USER << 'EOF'
source ~/.bashrc
cd $LFS/sources
tar -xf ncurses-6.5.tar.gz && cd ncurses-6.5
sed -i s/mawk// configure
mkdir build
pushd build
  ../configure
  make -C include
  make -C progs tic
popd
./configure --prefix=/usr                \
            --host=$LFS_TGT              \
            --build=$(./config.guess)    \
            --mandir=/usr/share/man      \
            --with-manpage-format=normal \
            --with-shared                \
            --without-normal             \
            --with-cxx-shared            \
            --without-debug              \
            --without-ada                \
            --disable-stripping
make && make DESTDIR=$LFS TIC_PATH=$(pwd)/build/progs/tic install
ln -sv libncursesw.so $LFS/usr/lib/libncurses.so
sed -e 's/^#if.*XOPEN.*$/#if 1/' \
    -i $LFS/usr/include/curses.h
EOF
}

temp_bash() {
    su - $LFS_USER << 'EOF'
source ~/.bashrc
cd $LFS/sources
tar -xf bash-5.2.32.tar.gz && cd bash-5.2.32
./configure --prefix=/usr                      \
            --build=$(sh support/config.guess) \
            --host=$LFS_TGT                    \
            --without-bash-malloc              \
            bash_cv_strtold_broken=no
make && make DESTDIR=$LFS install
ln -sv bash $LFS/bin/sh
EOF
}

temp_coreutils() {
    su - $LFS_USER << 'EOF'
source ~/.bashrc
cd $LFS/sources
tar -xf coreutils-9.5.tar.xz && cd coreutils-9.5
./configure --prefix=/usr                     \
            --host=$LFS_TGT                   \
            --build=$(build-aux/config.guess) \
            --enable-install-program=hostname \
            --enable-no-install-program=kill,uptime
make && make DESTDIR=$LFS install
mv -v $LFS/usr/bin/chroot              $LFS/usr/sbin
mkdir -pv $LFS/usr/share/man/man8
mv -v $LFS/usr/share/man/man1/chroot.1 $LFS/usr/share/man/man8/chroot.8
sed -i 's/"1"/"8"/'                    $LFS/usr/share/man/man8/chroot.8
EOF
}

temp_diffutils() {
    su - $LFS_USER << 'EOF'
source ~/.bashrc
cd $LFS/sources
tar -xf diffutils-3.10.tar.xz && cd diffutils-3.10
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(./build-aux/config.guess)
make && make DESTDIR=$LFS install
EOF
}

temp_file() {
    su - $LFS_USER << 'EOF'
source ~/.bashrc
cd $LFS/sources
tar -xf file-5.45.tar.gz && cd file-5.45
mkdir build
pushd build
  ../configure --disable-bzlib      \
               --disable-libseccomp \
               --disable-xzlib      \
               --disable-zlib
  make
popd
./configure --prefix=/usr --host=$LFS_TGT --build=$(./config.guess)
make FILE_COMPILE=$(pwd)/build/src/file
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/libmagic.la
EOF
}

temp_findutils() {
    su - $LFS_USER << 'EOF'
source ~/.bashrc
cd $LFS/sources
tar -xf findutils-4.10.0.tar.xz && cd findutils-4.10.0
./configure --prefix=/usr                   \
            --localstatedir=/var/lib/locate \
            --host=$LFS_TGT                 \
            --build=$(build-aux/config.guess)
make && make DESTDIR=$LFS install
EOF
}

temp_gawk() {
    su - $LFS_USER << 'EOF'
source ~/.bashrc
cd $LFS/sources
tar -xf gawk-5.3.0.tar.xz && cd gawk-5.3.0
sed -i 's/extras//' Makefile.in
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make && make DESTDIR=$LFS install
EOF
}

temp_grep() {
    su - $LFS_USER << 'EOF'
source ~/.bashrc
cd $LFS/sources
tar -xf grep-3.11.tar.xz && cd grep-3.11
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(./build-aux/config.guess)
make && make DESTDIR=$LFS install
EOF
}

temp_gzip() {
    su - $LFS_USER << 'EOF'
source ~/.bashrc
cd $LFS/sources
tar -xf gzip-1.13.tar.xz && cd gzip-1.13
./configure --prefix=/usr --host=$LFS_TGT
make && make DESTDIR=$LFS install
EOF
}

temp_make() {
    su - $LFS_USER << 'EOF'
source ~/.bashrc
cd $LFS/sources
tar -xf make-4.4.1.tar.gz && cd make-4.4.1
./configure --prefix=/usr   \
            --without-guile \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make && make DESTDIR=$LFS install
EOF
}

temp_patch() {
    su - $LFS_USER << 'EOF' 
source ~/.bashrc
cd $LFS/sources
tar -xf patch-2.7.6.tar.xz && cd patch-2.7.6
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make && make DESTDIR=$LFS install
EOF
}

temp_sed() {
    su - $LFS_USER << 'EOF'
source ~/.bashrc
cd $LFS/sources
tar -xf sed-4.9.tar.xz && cd sed-4.9
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(./build-aux/config.guess)
make && make DESTDIR=$LFS install
EOF
}

temp_tar() {
    su - $LFS_USER << 'EOF'
source ~/.bashrc
cd $LFS/sources
tar -xf tar-1.35.tar.xz && cd tar-1.35
./configure --prefix=/usr                     \
            --host=$LFS_TGT                   \
            --build=$(build-aux/config.guess)
make && make DESTDIR=$LFS install
EOF
}

temp_xz() {
    su - $LFS_USER << 'EOF'
source ~/.bashrc
cd $LFS/sources
tar -xf xz-5.6.2.tar.xz && cd xz-5.6.2
./configure --prefix=/usr                     \
            --host=$LFS_TGT                   \
            --build=$(build-aux/config.guess) \
            --disable-static                  \
            --docdir=/usr/share/doc/xz-5.6.2
make && make DESTDIR=$LFS install
rm -v $LFS/usr/lib/liblzma.la
EOF
}

temp_binutils_pass2() {
    su - $LFS_USER << 'EOF'
source ~/.bashrc
cd $LFS/sources
cd binutils-2.43.1
mv build build-pass-1
sed '6009s/$add_dir//' -i ltmain.sh
mkdir -pv build && cd build
../configure                   \
    --prefix=/usr              \
    --build=$(../config.guess) \
    --host=$LFS_TGT            \
    --disable-nls              \
    --enable-shared            \
    --enable-gprofng=no        \
    --disable-werror           \
    --enable-64-bit-bfd        \
    --enable-new-dtags         \
    --enable-default-hash-style=gnu
make
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
EOF
}

temp_gcc_pass2() {
    su - $LFS_USER << 'EOF'
source ~/.bashrc
cd $LFS/sources
cd gcc-14.2.0
tar -xf ../mpfr-4.2.1.tar.xz
mv -v mpfr-4.2.1 mpfr
tar -xf ../gmp-6.3.0.tar.xz
mv -v gmp-6.3.0 gmp
tar -xf ../mpc-1.3.1.tar.gz
mv -v mpc-1.3.1 mpc
case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
  ;;
esac
sed '/thread_header =/s/@.*@/gthr-posix.h/' \
    -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in
mv build build-pass-1
mkdir -pv build && cd build
../configure                                       \
    --build=$(../config.guess)                     \
    --host=$LFS_TGT                                \
    --target=$LFS_TGT                              \
    LDFLAGS_FOR_TARGET=-L$PWD/$LFS_TGT/libgcc      \
    --prefix=/usr                                  \
    --with-build-sysroot=$LFS                      \
    --enable-default-pie                           \
    --enable-default-ssp                           \
    --disable-nls                                  \
    --disable-multilib                             \
    --disable-libatomic                            \
    --disable-libgomp                              \
    --disable-libquadmath                          \
    --disable-libsanitizer                         \
    --disable-libssp                               \
    --disable-libvtv                               \
    --enable-languages=c,c++
make && make DESTDIR=$LFS install
ln -sv gcc $LFS/usr/bin/cc
EOF
}

channing_ownership() {
    cp -vr ./lfs-build.sh $LFS
    chown --from lfs -R root:root $LFS/{usr,lib,var,etc,bin,sbin,tools}
    case $(uname -m) in
        x86_64) chown --from lfs -R root:root $LFS/lib64 ;;
    esac
}   

virtual_kernel_fs() {
    mkdir -pv $LFS/{dev,proc,sys,run}
    if ! mountpoint -q "/$LFS/dev"; then
        mount -v --bind /dev $LFS/dev
    fi
    if ! mountpoint -q "$LFS/dev/pts"; then
        mount -vt devpts devpts -o gid=5,mode=0620 $LFS/dev/pts
    fi
    if ! mountpoint -q "$LFS/proc"; then
        mount -vt proc proc $LFS/proc
    fi
    if ! mountpoint -q "$LFS/sys"; then
        mount -vt sysfs sysfs $LFS/sys
    fi
    if ! mountpoint -q "$LFS/run"; then
        mount -vt tmpfs tmpfs $LFS/run
    fi
    #if [ -h $LFS/dev/shm ]; then
    if mountpoint -q "$LFS/dev/shm"; then
    install -v -d -m 1777 $LFS$(realpath /dev/shm)
    else
    mount -vt tmpfs -o nosuid,nodev tmpfs $LFS/dev/shm
    fi
}

chroot_environment() {
    chroot "$LFS" /usr/bin/env -i   \
    HOME=/root                  \
    TERM="$TERM"                \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin     \
    MAKEFLAGS="-j$(nproc)"      \
    TESTSUITEFLAGS="-j$(nproc)" \
    /bin/bash --login
}

create_directories() {
    mkdir -pv /{boot,home,mnt,opt,srv}
    mkdir -pv /etc/{opt,sysconfig}
    mkdir -pv /lib/firmware
    mkdir -pv /media/{floppy,cdrom}
    mkdir -pv /usr/{,local/}{include,src}
    mkdir -pv /usr/lib/locale
    mkdir -pv /usr/local/{bin,lib,sbin}
    mkdir -pv /usr/{,local/}share/{color,dict,doc,info,locale,man}
    mkdir -pv /usr/{,local/}share/{misc,terminfo,zoneinfo}
    mkdir -pv /usr/{,local/}share/man/man{1..8}
    mkdir -pv /var/{cache,local,log,mail,opt,spool}
    mkdir -pv /var/lib/{color,misc,locate}

    if [ ! -L /var/run ]; then
        ln -sfv /run /var/run
    fi

    if [ ! -L /var/lock ]; then
        ln -sfv /run/lock /var/lock
    fi

    install -dv -m 0750 /root
    install -dv -m 1777 /tmp /var/tmp    
}

build_temporary_tools_chroot(){
    channing_ownership
    virtual_kernel_fs
    chroot_environment
}

creating_essential_files_links() {
    if [ ! -L /etc/mtab ]; then
        ln -sfv /proc/self/mounts /etc/mtab
    fi

    cat > /etc/hosts << EOF
127.0.0.1  localhost $(hostname)
::1        localhost
EOF

cat > /etc/passwd << "EOF"
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/usr/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
EOF

cat > /etc/group << "EOF"
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
input:x:24:
mail:x:34:
kvm:x:61:
uuidd:x:80:
wheel:x:97:
users:x:999:
nogroup:x:65534:
EOF

localedef -i C -f UTF-8 C.UTF-8

echo "tester:x:101:101::/home/tester:/bin/bash" >> /etc/passwd
echo "tester:x:101:" >> /etc/group
install -o tester -d /home/tester

clear
echo "Ahora se va ejecutar un nuevo sheel para continuar con la construcción del sistema base."
echo ""
echo "Ejecute el script con la opción 'builddist' para continuar."
echo ""

exec /usr/bin/bash --login
}

creating_essential_files_links2() {
    touch /var/log/{btmp,lastlog,faillog,wtmp}
    chgrp -v utmp /var/log/lastlog
    chmod -v 664  /var/log/lastlog
    chmod -v 600  /var/log/btmp   
}

notify_build_base() {
    clear
    echo "Construcción de herramientas temporales completada."
    echo ""
    echo "Se pasa a modo chroot. Ejecute el script (desde el raíz) con la opción 'buildbase' para continuar."
    echo ""
}

# Función para construir herramientas temporales
buildtools() {
    initialize
#TODO descomentar en la versión final.    
    check_dependencies
    download_sources
    prepare_environment
    build_temporary_tools

    notify_build_base
    build_temporary_tools_chroot
}

# Función para construir el sistema base
buildbase() {
    create_directories
    creating_essential_files_links
    echo "Instalación completada. Revisa el log en $LOG_FILE para más detalles."
}

build_gettext() {
    cd /sources
    tar -xf gettext-0.22.5.tar.xz && cd gettext-0.22.5
    ./configure --disable-shared
    make
    cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin
}

build_bison() {
    cd /sources
    tar -xf bison-3.8.2.tar.xz && cd bison-3.8.2
    ./configure --prefix=/usr \
            --docdir=/usr/share/doc/bison-3.8.2    
    make && make install
}

build_perl() {
    cd /sources
    tar -xf perl-5.40.0.tar.xz && cd perl-5.40.0
    sh Configure -des                                     \
             -D prefix=/usr                               \
             -D vendorprefix=/usr                         \
             -D useshrplib                                \
             -D privlib=/usr/lib/perl5/5.40/core_perl     \
             -D archlib=/usr/lib/perl5/5.40/core_perl     \
             -D sitelib=/usr/lib/perl5/5.40/site_perl     \
             -D sitearch=/usr/lib/perl5/5.40/site_perl    \
             -D vendorlib=/usr/lib/perl5/5.40/vendor_perl \
             -D vendorarch=/usr/lib/perl5/5.40/vendor_perl
    make && make install
}

build_python() {
    cd /sources
    tar -xf Python-3.12.5.tar.xz && cd Python-3.12.5
    ./configure --prefix=/usr   \
                --enable-shared \
                --without-ensurepip
    make && make install
}

build_texinfo() {
    cd /sources
    tar -xf texinfo-7.1.tar.xz && cd texinfo-7.1
    ./configure --prefix=/usr
    make && make install
}

build_util_linux() {
    cd /sources
    tar -xf util-linux-2.40.2.tar.xz && cd util-linux-2.40.2
    mkdir -pv /var/lib/hwclock
    ./configure --libdir=/usr/lib     \
                --runstatedir=/run    \
                --disable-chfn-chsh   \
                --disable-login       \
                --disable-nologin     \
                --disable-su          \
                --disable-setpriv     \
                --disable-runuser     \
                --disable-pylibmount  \
                --disable-static      \
                --disable-liblastlog2 \
                --without-python      \
                ADJTIME_PATH=/var/lib/hwclock/adjtime \
                --docdir=/usr/share/doc/util-linux-2.40.2
    make && make install
}

cleaning_and_backup() {
    rm -rf /usr/share/{info,man,doc}/*
    find /usr/{lib,libexec} -name \*.la -delete
    rm -rf /tools

    #TODO: Backup de los archivos de configuración
    #       parámetros: backup, restore y continue_after_backup
}

#package_management() {
#    #TODO: Instalar gestor de paquetes
#}

install_man_pages() {
    cd /sources
    tar -xf man-pages-6.9.1.tar.xz && cd man-pages-6.9.1
    rm -v man3/crypt*
    make prefix=/usr install
}

install_iana_etc() {
    cd /sources
    tar -xf iana-etc-20240806.tar.gz && cd iana-etc-20240806
    cp services protocols /etc
}

install_glibc() {
    cd /sources/glibc-2.40
    set +e # Se desactiva la opción de parada por error
    patch -Np1 -i ../glibc-2.40-fhs-1.patch
    set -e # Se activa la opción de parada por error

    mv build build-pass-1
    mkdir -v build && cd build
    echo "rootsbindir=/usr/sbin" > configparms
    ../configure --prefix=/usr                        \
             --disable-werror                         \
             --enable-kernel=4.19                     \
             --enable-stack-protector=strong          \
             --disable-nscd                           \
             libc_cv_slibdir=/usr/lib
    make

    set +e # Se desactiva la opción de parada por error
    make check || false
    grep "Timed out" $(find -name \*.out)  # TODO: Comprobar por qué se para aquí
    set -e # Se activa la opción de parada por error
    touch /etc/ld.so.conf
    sed '/test-installation/s@$(PERL)@echo not running@' -i ../Makefile
    make install
    sed '/RTLDLIST=/s@/usr@@g' -i /usr/bin/ldd

    # Configuración de localización

    localedef -i C -f UTF-8 C.UTF-8
    localedef -i cs_CZ -f UTF-8 cs_CZ.UTF-8
    localedef -i de_DE -f ISO-8859-1 de_DE
    localedef -i de_DE@euro -f ISO-8859-15 de_DE@euro
    localedef -i de_DE -f UTF-8 de_DE.UTF-8
    localedef -i el_GR -f ISO-8859-7 el_GR
    localedef -i en_GB -f ISO-8859-1 en_GB
    localedef -i en_GB -f UTF-8 en_GB.UTF-8
    localedef -i en_HK -f ISO-8859-1 en_HK
    localedef -i en_PH -f ISO-8859-1 en_PH
    localedef -i en_US -f ISO-8859-1 en_US
    localedef -i en_US -f UTF-8 en_US.UTF-8
    localedef -i es_ES -f ISO-8859-15 es_ES@euro
    localedef -i es_MX -f ISO-8859-1 es_MX
    localedef -i fa_IR -f UTF-8 fa_IR
    localedef -i fr_FR -f ISO-8859-1 fr_FR
    localedef -i fr_FR@euro -f ISO-8859-15 fr_FR@euro
    localedef -i fr_FR -f UTF-8 fr_FR.UTF-8
    localedef -i is_IS -f ISO-8859-1 is_IS
    localedef -i is_IS -f UTF-8 is_IS.UTF-8
    localedef -i it_IT -f ISO-8859-1 it_IT
    localedef -i it_IT -f ISO-8859-15 it_IT@euro
    localedef -i it_IT -f UTF-8 it_IT.UTF-8
    localedef -i ja_JP -f EUC-JP ja_JP
    localedef -i ja_JP -f SHIFT_JIS ja_JP.SJIS 2> /dev/null || true
    localedef -i ja_JP -f UTF-8 ja_JP.UTF-8
    localedef -i nl_NL@euro -f ISO-8859-15 nl_NL@euro
    localedef -i ru_RU -f KOI8-R ru_RU.KOI8-R
    localedef -i ru_RU -f UTF-8 ru_RU.UTF-8
    localedef -i se_NO -f UTF-8 se_NO.UTF-8
    localedef -i ta_IN -f UTF-8 ta_IN.UTF-8
    localedef -i tr_TR -f UTF-8 tr_TR.UTF-8
    localedef -i zh_CN -f GB18030 zh_CN.GB18030
    localedef -i zh_HK -f BIG5-HKSCS zh_HK.BIG5-HKSCS
    localedef -i zh_TW -f UTF-8 zh_TW.UTF-8

    make localedata/install-locales

    localedef -i C -f UTF-8 C.UTF-8
    localedef -i ja_JP -f SHIFT_JIS ja_JP.SJIS 2> /dev/null || true

    # Configuración de ficheros

    cat > /etc/nsswitch.conf << "EOF"
# Begin /etc/nsswitch.conf

passwd: files
group: files
shadow: files

hosts: files dns
networks: files

protocols: files
services: files
ethers: files
rpc: files

# End /etc/nsswitch.conf
EOF

    # Configuración de tiempo

    tar -xf ../../tzdata2024a.tar.gz

    ZONEINFO=/usr/share/zoneinfo
    mkdir -pv $ZONEINFO/{posix,right}

    for tz in etcetera southamerica northamerica europe africa antarctica  \
            asia australasia backward; do
        zic -L /dev/null   -d $ZONEINFO       ${tz}
        zic -L /dev/null   -d $ZONEINFO/posix ${tz}
        zic -L leapseconds -d $ZONEINFO/right ${tz}
    done

    cp -v zone.tab zone1970.tab iso3166.tab $ZONEINFO
    zic -d $ZONEINFO -p America/New_York
    unset ZONEINFO

    # TODO: parametrizar

    tzselect
    ln -sfv /usr/share/zoneinfo/Spain/Europe /etc/localtime

    # Configuración de cargador dinámico

    cat > /etc/ld.so.conf << "EOF"
# Begin /etc/ld.so.conf
/usr/local/lib
/opt/lib

EOF

cat >> /etc/ld.so.conf << "EOF"
# Add an include directory
include /etc/ld.so.conf.d/*.conf

EOF

mkdir -pv /etc/ld.so.conf.d
}

install_zlib() {
    cd /sources
    tar -xf zlib-1.3.1.tar.gz && cd zlib-1.3.1
    ./configure --prefix=/usr
    make && make check && make install
    rm -fv /usr/lib/libz.a
}

install_bzip() {
    cd /sources
    tar -xf bzip2-1.0.8.tar.gz && cd bzip2-1.0.8
    patch -Np1 -i ../bzip2-1.0.8-install_docs-1.patch
    sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
    sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile

    make -f Makefile-libbz2_so
    make clean
    make
    make PREFIX=/usr install

    cp -av libbz2.so.* /usr/lib
    ln -sv libbz2.so.1.0.8 /usr/lib/libbz2.so

    cp -v bzip2-shared /usr/bin/bzip2
    for i in /usr/bin/{bzcat,bunzip2}; do
    ln -sfv bzip2 $i
    done

    rm -fv /usr/lib/libbz2.a
}

install_xz() {
    cd /sources/xz-5.6.2
    ./configure --prefix=/usr    \
                --disable-static \
                --docdir=/usr/share/doc/xz-5.6.2
    make && make check && make install
}

install_lz4() {
    cd /sources
    tar -xf lz4-1.10.0.tar.gz && cd lz4-1.10.0
    make BUILD_STATIC=no PREFIX=/usr
    make -j1 check
    make BUILD_STATIC=no PREFIX=/usr install
}

install_zstd() {
    cd /sources
    tar -xf zstd-1.5.6.tar.gz && cd zstd-1.5.6
    make prefix=/usr
    make check
    make prefix=/usr install
    rm -v /usr/lib/libzstd.a
}

install_file() {
    cd /sources/file-5.45
    ./configure --prefix=/usr
    make && make check && make install
}

install_readline() {
    cd /sources
    tar -xf readline-8.2.13.tar.gz && cd readline-8.2.13
    sed -i '/MV.*old/d' Makefile.in
    sed -i '/{OLDSUFF}/c:' support/shlib-install
    sed -i 's/-Wl,-rpath,[^ ]*//' support/shobj-conf
    ./configure --prefix=/usr    \
                --disable-static \
                --with-curses     \
                --docdir=/usr/share/doc/readline-8.2.13
    make SHLIB_LIBS="-lncursesw"
    make SHLIB_LIBS="-lncursesw" install
    install -v -m644 doc/*.{ps,pdf,html,dvi} /usr/share/doc/readline-8.2.13
}

install_m4() {
    cd /sources/m4-1.4.19
    ./configure --prefix=/usr
    make && make check && make install
}

install_bc() {
    cd /sources
    tar -xf bc-6.7.6.tar.xz && cd bc-6.7.6
    CC=gcc ./configure --prefix=/usr -G -O3 -r
    make && make test && make install
}

install_flex() {
    cd /sources
    tar -xf flex-2.6.4.tar.gz && cd flex-2.6.4
    ./configure --prefix=/usr \
            --docdir=/usr/share/doc/flex-2.6.4 \
            --disable-static    
    make && make check && make install
    ln -sv flex   /usr/bin/lex
    ln -sv flex.1 /usr/share/man/man1/lex.1
}

install_tcl() {
    cd /sources
    tar -xf tcl8.6.14-src.tar.gz && cd tcl8.6.14
    SRCDIR=$(pwd)
    cd unix
    ./configure --prefix=/usr           \
                --mandir=/usr/share/man \
                --disable-rpath
    make

    sed -e "s|$SRCDIR/unix|/usr/lib|" \
        -e "s|$SRCDIR|/usr/include|"  \
        -i tclConfig.sh

    sed -e "s|$SRCDIR/unix/pkgs/tdbc1.1.7|/usr/lib/tdbc1.1.7|" \
        -e "s|$SRCDIR/pkgs/tdbc1.1.7/generic|/usr/include|"    \
        -e "s|$SRCDIR/pkgs/tdbc1.1.7/library|/usr/lib/tcl8.6|" \
        -e "s|$SRCDIR/pkgs/tdbc1.1.7|/usr/include|"            \
        -i pkgs/tdbc1.1.7/tdbcConfig.sh

    sed -e "s|$SRCDIR/unix/pkgs/itcl4.2.4|/usr/lib/itcl4.2.4|" \
        -e "s|$SRCDIR/pkgs/itcl4.2.4/generic|/usr/include|"    \
        -e "s|$SRCDIR/pkgs/itcl4.2.4|/usr/include|"            \
        -i pkgs/itcl4.2.4/itclConfig.sh

    unset SRCDIR

    make test
    make install
    chmod -v u+w /usr/lib/libtcl8.6.so
    make install-private-headers
    ln -sfv tclsh8.6 /usr/bin/tclsh
    mv /usr/share/man/man3/{Thread,Tcl_Thread}.3

    cd ..
    tar -xf ../tcl8.6.14-html.tar.gz --strip-components=1
    mkdir -v -p /usr/share/doc/tcl-8.6.14
    cp -v -r  ./html/* /usr/share/doc/tcl-8.6.14
}

install_spect() {
    cd /sources
    tar -xf expect5.45.4.tar.gz && cd expect5.45.4
    python3 -c 'from pty import spawn; spawn(["echo", "ok"])'
    patch -Np1 -i ../expect-5.45.4-gcc14-1.patch
    ./configure --prefix=/usr           \
            --with-tcl=/usr/lib     \
            --enable-shared         \
            --disable-rpath         \
            --mandir=/usr/share/man \
            --with-tclinclude=/usr/include
    make && make test && make install
    ln -svf expect5.45.4/libexpect5.45.4.so /usr/lib
}

install_dejaGNU() {
    cd /sources
    tar -xf dejagnu-1.6.3.tar.gz && cd dejagnu-1.6.3
    mkdir -v build && cd build
    ../configure --prefix=/usr
    makeinfo --html --no-split -o doc/dejagnu.html ../doc/dejagnu.texi
    makeinfo --plaintext       -o doc/dejagnu.txt  ../doc/dejagnu.texi
    make check
    make install
    install -v -dm755  /usr/share/doc/dejagnu-1.6.3
    install -v -m644   doc/dejagnu.{html,txt} /usr/share/doc/dejagnu-1.6.3
}

install_pkgconf() {
    cd /sources
    tar -xf pkgconf-2.3.0.tar.xz && cd pkgconf-2.3.0
    ./configure --prefix=/usr              \
            --disable-static           \
            --docdir=/usr/share/doc/pkgconf-2.3.0
    make && make install
    ln -sv pkgconf   /usr/bin/pkg-config
    ln -sv pkgconf.1 /usr/share/man/man1/pkg-config.1
}

install_binutils() {
    cd /sources
    tar -xf binutils-2.43.1.tar.xz
    cd binutils-2.43.1
    mv build build-pass-2
    mkdir -v build
    cd build
    ../configure --prefix=/usr   \
             --sysconfdir=/etc   \
             --enable-gold       \
             --enable-ld=default \
             --enable-plugins    \
             --enable-shared     \
             --disable-werror    \
             --enable-64-bit-bfd \
             --enable-new-dtags  \
             --with-system-zlib  \
             --enable-default-hash-style=gnu
    make tooldir=/usr
    set +e # Se desactiva la opción de parada por error
    make -k check
    grep '^FAIL:' $(find -name '*.log')
    set -e # Se activa la opción de parada por error
    make tooldir=/usr install
    rm -fv /usr/lib/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.a
}

install_gmp() {
    cd /sources
    tar -xf gmp-6.3.0.tar.xz && cd gmp-6.3.0
    # If you are building for 32-bit x86, but you have a CPU which is 
    # capable of running 64-bit code and you have specified CFLAGS in
    # the environment, the configure script will attempt to configure 
    # for 64-bits and fail. Avoid this by invoking the configure 
    # command below with
    # ABI=32 ./configure ...    
    ./configure --prefix=/usr    \
            --enable-cxx     \
            --disable-static \
            --docdir=/usr/share/doc/gmp-6.3.0
    make && make html
    make check 2>&1 | tee gmp-check-log
    awk '/# PASS:/{total+=$3} ; END{print total}' gmp-check-log
    make install
    make install-html
}

install_mpfr() {
    cd /sources
    tar -xf mpfr-4.2.1.tar.xz && cd mpfr-4.2.1
    ./configure --prefix=/usr        \
                --disable-static     \
                --enable-thread-safe \
                --docdir=/usr/share/doc/mpfr-4.2.1
    make && make html
    make check
    make install
    make install-html
}

install_mpc() {
    cd /sources
    tar -xf mpc-1.3.1.tar.gz && cd mpc-1.3.1
    ./configure --prefix=/usr    \
                --disable-static \
                --docdir=/usr/share/doc/mpc-1.3.1
    make && make html
    make check
    make install
    make install-html
}

install_attr() {
    cd /sources
    tar -xf attr-2.5.2.tar.gz && cd attr-2.5.2
    ./configure --prefix=/usr     \
                --disable-static  \
                --sysconfdir=/etc \
                --docdir=/usr/share/doc/attr-2.5.2
    make
    make check
    make install
    # TODO: Comprobar si es necesario
    # mv -v /usr/lib/libattr.so.* /lib
    # ln -sfv ../../lib/$(readlink /usr/lib/libattr.so) /usr/lib/libattr.so
}

install_acl() {
    cd /sources
    tar -xf acl-2.3.2.tar.xz && cd acl-2.3.2
    ./configure --prefix=/usr         \
                --disable-static      \
                --docdir=/usr/share/doc/acl-2.3.2
    make
    make install
}

install_libcap() {
    cd /sources
    tar -xf libcap-2.70.tar.xz && cd libcap-2.70
    sed -i '/install -m.*STA/d' libcap/Makefile
    make prefix=/usr lib=lib
    make test
    make prefix=/usr lib=lib install
}

install_libxcrypt() {
    cd /sources
    tar -xf libxcrypt-4.4.36.tar.xz && cd libxcrypt-4.4.36
    ./configure --prefix=/usr                \
                --enable-hashes=strong,glibc \
                --enable-obsolete-api=no     \
                --disable-static             \
                --disable-failure-tokens
    make
    make check
    make install

    make distclean
    ./configure --prefix=/usr                \
                --enable-hashes=strong,glibc \
                --enable-obsolete-api=glibc  \
                --disable-static             \
                --disable-failure-tokens
    make
    cp -av --remove-destination .libs/libcrypt.so.1* /usr/lib
}

install_shadow() {
    cd /sources
    tar -xf shadow-4.16.0.tar.xz && cd shadow-4.16.0
    sed -i 's/groups$(EXEEXT) //' src/Makefile.in
    find man -name Makefile.in -exec sed -i 's/groups\.1 / /'   {} \;
    find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
    find man -name Makefile.in -exec sed -i 's/passwd\.5 / /'   {} \; 
    sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD YESCRYPT:' \
        -e 's:/var/spool/mail:/var/mail:'                   \
        -e '/PATH=/{s@/sbin:@@;s@/bin:@@}'                  \
        -i etc/login.defs
    # Cracklib support
    sed -i 's:DICTPATH.*:DICTPATH\t/lib/cracklib/pw_dict:' etc/login.defs

    touch /usr/bin/passwd
    ./configure --sysconfdir=/etc   \
                --disable-static    \
                --with-{b,yes}crypt \
                --without-libbsd    \
                --with-group-name-max-length=32
    make
    make exec_prefix=/usr install
    make -C man install-man

    # Configuración de ficheros
    pwconv
    grpconv
    mkdir -p /etc/default
    useradd -D --gid 999
    sed -i '/MAIL/s/yes/no/' /etc/default/useradd

    passwd root
}

install_gcc() {
    cd /sources
    #tar -xf gcc-14.2.0.tar.xz 
    cd gcc-14.2.0
    mv build build-pass-2

    case $(uname -m) in
    x86_64)
        sed -e '/m64=/s/lib64/lib/' \
            -i.orig gcc/config/i386/t-linux64
    ;;
    esac

    mkdir -v build && cd build
    ../configure --prefix=/usr            \
                LD=ld                    \
                --enable-languages=c,c++ \
                --enable-default-pie     \
                --enable-default-ssp     \
                --enable-host-pie        \
                --disable-multilib       \
                --disable-bootstrap      \
                --disable-fixincludes    \
                --with-system-zlib
    make
    ulimit -s -H unlimited
    sed -e '/cpython/d'               -i ../gcc/testsuite/gcc.dg/plugin/plugin.exp
    sed -e 's/no-pic /&-no-pie /'     -i ../gcc/testsuite/gcc.target/i386/pr113689-1.c
    sed -e 's/300000/(1|300000)/'     -i ../libgomp/testsuite/libgomp.c-c++-common/pr109062.c
    sed -e 's/{ target nonpic } //' \
        -e '/GOTPCREL/d'              -i ../gcc/testsuite/gcc.target/i386/fentryname3.c
    chown -R tester .
    su tester -c "PATH=$PATH make -k check"
    ../contrib/test_summary
    make install
    chown -v -R root:root \
    /usr/lib/gcc/$(gcc -dumpmachine)/14.2.0/include{,-fixed}
    ln -svr /usr/bin/cpp /usr/lib
    ln -sv gcc.1 /usr/share/man/man1/cc.1
    ln -sfv ../../libexec/gcc/$(gcc -dumpmachine)/14.2.0/liblto_plugin.so \
        /usr/lib/bfd-plugins/
    echo 'int main(){}' > dummy.c
    cc dummy.c -v -Wl,--verbose &> dummy.log
    readelf -l a.out | grep ': /lib'
    # TODO: Comprobar el siguiente resultado:
    # [Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]
    grep -E -o '/usr/lib.*/S?crt[1in].*succeeded' dummy.log
    # TODO: Comprobar el siguiente resultado:
    #/usr/lib/gcc/x86_64-pc-linux-gnu/14.2.0/../../../../lib/Scrt1.o succeeded
    # /usr/lib/gcc/x86_64-pc-linux-gnu/14.2.0/../../../../lib/crti.o succeeded
    # /usr/lib/gcc/x86_64-pc-linux-gnu/14.2.0/../../../../lib/crtn.o succeeded
    grep -B4 '^ /usr/include' dummy.log
    # TODO: Comprobar el siguiente resultado:
    # #include <...> search starts here:#include <...> search starts here:
    # /usr/lib/gcc/x86_64-pc-linux-gnu/14.2.0/include
    # /usr/local/include
    # /usr/lib/gcc/x86_64-pc-linux-gnu/14.2.0/include-fixed
    # /usr/include
    grep 'SEARCH.*/usr/lib' dummy.log |sed 's|; |\n|g'
    # TODO: Comprobar resultados según lo establecido en LBS v12.2 - Chapter 8 - GCC-14.2.0
    grep "/lib.*/libc.so.6 " dummy.log
    grep found dummy.log
    rm -v dummy.c a.out dummy.log
    mkdir -pv /usr/share/gdb/auto-load/usr/lib
    mv -v /usr/lib/*gdb.py /usr/share/gdb/auto-load/usr/lib
}

install_ncurses() {
    cd /sources
    # tar -xf ncurses-6.3.tar.gz 
    cd ncurses-6.5
    mv build build-pass-2
    ./configure --prefix=/usr           \
                --mandir=/usr/share/man \
                --with-shared           \
                --without-debug         \
                --without-normal        \
                --with-cxx-shared       \
                --enable-pc-files       \
                --with-pkg-config-libdir=/usr/lib/pkgconfig
    make
    make DESTDIR=$PWD/dest install
    install -vm755 dest/usr/lib/libncursesw.so.6.5 /usr/lib
    rm -v  dest/usr/lib/libncursesw.so.6.5
    sed -e 's/^#if.*XOPEN.*$/#if 1/' \
        -i dest/usr/include/curses.h
    cp -av dest/* /

    for lib in ncurses form panel menu ; do
        ln -sfv lib${lib}w.so /usr/lib/lib${lib}.so
        ln -sfv ${lib}w.pc    /usr/lib/pkgconfig/${lib}.pc
    done

    ln -sfv libncursesw.so /usr/lib/libcurses.so
    cp -v -R doc -T /usr/share/doc/ncurses-6.5

    make distclean
    ./configure --prefix=/usr    \
                --with-shared    \
                --without-normal \
                --without-debug  \
                --without-cxx-binding \
                --with-abi-version=5
    make sources libs
    cp -av lib/lib*.so.5* /usr/lib
}

install_sed() {
    cd /sources/sed-4.9
    ./configure --prefix=/usr
    make
    make html
    chown -R tester .
    su tester -c "PATH=$PATH make check"
    make install
    install -d -m755           /usr/share/doc/sed-4.9
    install -m644 doc/sed.html /usr/share/doc/sed-4.9
}

install_psmisc() {
    cd /sources
    tar -xf psmisc-23.7.tar.xz && cd psmisc-23.7
    ./configure --prefix=/usr
    make
    make check
    make install
}

install_gettext() {
    cd /sources/gettext-0.22.5
    ./configure --prefix=/usr    \
                --disable-static \
                --docdir=/usr/share/doc/gettext-0.22.5
    make
    make check
    make install
    chmod -v 0755 /usr/lib/preloadable_libintl.so
}

install_bison() {
    cd /sources/bison-3.8.2
    ./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.8.2
    make
    make check
    make install
}

install_grep() {
    cd /sources/grep-3.11
    sed -i "s/echo/#echo/" src/egrep.sh
    ./configure --prefix=/usr
    make
    make check
    make install
}

install_bash() {
    cd /sources/bash-5.2.32
    ./configure --prefix=/usr             \
                --without-bash-malloc     \
                --with-installed-readline \
                bash_cv_strtold_broken=no \
                --docdir=/usr/share/doc/bash-5.2.32
    make
    chown -Rv tester .
    su -s /usr/bin/expect tester << "EOF"
set timeout -1
spawn make tests
expect eof
lassign [wait] _ _ _ value
exit $value
EOF
    make install
    ln -sv bash /usr/bin/sh
    # TODO: Comprobar si es necesario
    # exec /usr/bin/bash --login
}

install_libtool() {
    cd /sources
    tar -xf libtool-2.4.7.tar.xz && cd libtool-2.4.7
    ./configure --prefix=/usr
    make
    set +x
    set +e
    make -k check
    make install
    rm -fv /usr/lib/libltdl.a
    set -e    
}

install_gdbm() {
    cd /sources
    tar -xf gdbm-1.24.tar.gz && cd gdbm-1.24
    ./configure --prefix=/usr    \
                --disable-static \
                --enable-libgdbm-compat
    make
    make check
    make install
}

install_gperf() {
    cd /sources
    tar -xf gperf-3.1.tar.gz && cd gperf-3.1
    ./configure --prefix=/usr --docdir=/usr/share/doc/gperf-3.1
    make
    make -j1 check
    make install
}

install_expat() {
    cd /sources
    tar -xf expat-2.6.2.tar.xz && cd expat-2.6.2
    ./configure --prefix=/usr    \
                --disable-static \
                --docdir=/usr/share/doc/expat-2.6.2
    make
    make check
    make install
    install -v -m644 doc/*.{html,css} /usr/share/doc/expat-2.6.2
}

install_inetutils() {
    cd /sources
    tar -xf inetutils-2.5.tar.xz && cd inetutils-2.5
    sed -i 's/def HAVE_TERMCAP_TGETENT/ 1/' telnet/telnet.c
    ./configure --prefix=/usr        \
                --bindir=/usr/bin    \
                --localstatedir=/var \
                --disable-logger     \
                --disable-whois      \
                --disable-rcp        \
                --disable-rexec      \
                --disable-rlogin     \
                --disable-rsh        \
                --disable-servers
    make
    make check
    make install
    mv -v /usr/{,s}bin/ifconfig
}

install_less() {
    cd /sources
    tar -xf less-661.tar.gz && cd less-661
    ./configure --prefix=/usr --sysconfdir=/etc
    make
    make check
    make install
}

install_perl() {
    cd /sources/perl-5.40.0
    export BUILD_ZLIB=False
    export BUILD_BZIP2=0
    sh Configure -des                                          \
                -D prefix=/usr                                \
                -D vendorprefix=/usr                          \
                -D privlib=/usr/lib/perl5/5.40/core_perl      \
                -D archlib=/usr/lib/perl5/5.40/core_perl      \
                -D sitelib=/usr/lib/perl5/5.40/site_perl      \
                -D sitearch=/usr/lib/perl5/5.40/site_perl     \
                -D vendorlib=/usr/lib/perl5/5.40/vendor_perl  \
                -D vendorarch=/usr/lib/perl5/5.40/vendor_perl \
                -D man1dir=/usr/share/man/man1                \
                -D man3dir=/usr/share/man/man3                \
                -D pager="/usr/bin/less -isR"                 \
                -D useshrplib                                 \
                -D usethreads
    make
    TEST_JOBS=$(nproc) make test_harness
    make install
    unset BUILD_ZLIB BUILD_BZIP2
}

install_xml_parser() {
    cd /sources
    tar -xf XML-Parser-2.47.tar.gz && cd XML-Parser-2.47
    perl Makefile.PL
    make
    make test
    make install
}

install_intltool() {
    cd /sources
    tar -xf intltool-0.51.0.tar.gz && cd intltool-0.51.0
    sed -i 's:\\\${:\\\$\\{:' intltool-update.in
    ./configure --prefix=/usr
    make
    make check
    make install
    install -v -Dm644 doc/I18N-HOWTO /usr/share/doc/intltool-0.51.0/I18N-HOWTO
}

install_autoconf() {
    cd /sources
    tar -xf autoconf-2.72.tar.xz && cd autoconf-2.72
    ./configure --prefix=/usr
    make
    make check
    make install
}

install_automake() {
    cd /sources
    tar -xf automake-1.17.tar.xz && cd automake-1.17
    ./configure --prefix=/usr --docdir=/usr/share/doc/automake-1.17
    make
    make -j$(($(nproc)>4?$(nproc):4)) check
    make install
}

install_openssl() {
    cd /sources
    tar -xf openssl-3.3.1.tar.gz && cd openssl-3.3.1
    ./config --prefix=/usr         \
            --openssldir=/etc/ssl \
            --libdir=lib          \
            shared                \
            zlib-dynamic
    make
    HARNESS_JOBS=$(nproc) make test
    sed -i '/INSTALL_LIBS/s/libcrypto.a libssl.a//' Makefile
    make MANSUFFIX=ssl install
    mv -v /usr/share/doc/openssl /usr/share/doc/openssl-3.3.1
    cp -vfr doc/* /usr/share/doc/openssl-3.3.1
}

install_kmod() {
    cd /sources
    tar -xf kmod-33.tar.xz && cd kmod-33
    ./configure --prefix=/usr     \
                --sysconfdir=/etc \
                --with-openssl    \
                --with-xz         \
                --with-zstd       \
                --with-zlib       \
                --disable-manpages
    make
    make install

    for target in depmod insmod modinfo modprobe rmmod; do
    ln -sfv ../bin/kmod /usr/sbin/$target
    rm -fv /usr/bin/$target
    done
}

install_libelf_from_elfutils() {
    cd /sources
    tar -xf elfutils-0.191.tar.bz2 && cd elfutils-0.191
    ./configure --prefix=/usr                \
                --disable-debuginfod         \
                --enable-libdebuginfod=dummy
    make
    make check
    make -C libelf install
    install -vm644 config/libelf.pc /usr/lib/pkgconfig
    rm /usr/lib/libelf.a
}

install_libffi() {
    cd /sources
    tar -xf libffi-3.4.6.tar.gz && cd libffi-3.4.6
    ./configure --prefix=/usr          \
                --disable-static       \
                --with-gcc-arch=native
    make
    make check
    make install
}

install_python() {
    cd /sources/Python-3.12.5
    ./configure --prefix=/usr        \
                --enable-shared      \
                --with-system-expat  \
                --enable-optimizations
    make
    make test TESTOPTS="--timeout 120"
    make install
    cat > /etc/pip.conf << EOF
[global]
root-user-action = ignore
disable-pip-version-check = true
EOF
    install -v -dm755 /usr/share/doc/python-3.12.5/html

    tar --no-same-owner \
        -xvf ../python-3.12.5-docs-html.tar.bz2
    cp -R --no-preserve=mode python-3.12.5-docs-html/* \
        /usr/share/doc/python-3.12.5/html
}

install_flitcore() {
    cd /sources
    tar -xf flit_core-3.9.0.tar.gz && cd flit_core-3.9.0
    pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
    pip3 install --no-index --find-links dist flit_core
}

install_whell() {
    cd /sources
    tar -xf wheel-0.44.0.tar.gz && cd wheel-0.44.0
    pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
    pip3 install --no-index --find-links dist wheel
}

install_setuptools() {
    cd /sources
    tar -xf setuptools-72.2.0.tar.gz && cd setuptools-72.2.0
    pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
    pip3 install --no-index --find-links dist setuptools
}

install_ninja() {
    cd /sources
    tar -xf ninja-1.12.1.tar.gz && cd ninja-1.12.1
    export NINJAJOBS=4
    sed -i '/int Guess/a \
        int   j = 0;\
        char* jobs = getenv( "NINJAJOBS" );\
        if ( jobs != NULL ) j = atoi( jobs );\
        if ( j > 0 ) return j;\
        ' src/ninja.cc
    python3 configure.py --bootstrap
    install -vm755 ninja /usr/bin/
    install -vDm644 misc/bash-completion /usr/share/bash-completion/completions/ninja
    install -vDm644 misc/zsh-completion  /usr/share/zsh/site-functions/_ninja
}

install_meson() {
    cd /sources
    tar -xf meson-1.5.1.tar.gz && cd meson-1.5.1
    pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
    pip3 install --no-index --find-links dist meson
    install -vDm644 data/shell-completions/bash/meson /usr/share/bash-completion/completions/meson
    install -vDm644 data/shell-completions/zsh/_meson /usr/share/zsh/site-functions/_meson
}

install_coreutils() {
    cd /sources/coreutils-9.5
    patch -Np1 -i ../coreutils-9.5-i18n-2.patch
    autoreconf -fiv
    FORCE_UNSAFE_CONFIGURE=1 ./configure \
                --prefix=/usr            \
                --enable-no-install-program=kill,uptime
    make
    make NON_ROOT_USERNAME=tester check-root
    groupadd -g 102 dummy -U tester
    chown -R tester . 
    su tester -c "PATH=$PATH make -k RUN_EXPENSIVE_TESTS=yes check" \
        < /dev/null
    groupdel dummy
    make install
    mv -v /usr/bin/chroot /usr/sbin
    mv -v /usr/share/man/man1/chroot.1 /usr/share/man/man8/chroot.8
    sed -i 's/"1"/"8"/' /usr/share/man/man8/chroot.8
}

install_check() {
    cd /sources
    tar -xf check-0.15.2.tar.gz && cd check-0.15.2
    ./configure --prefix=/usr --disable-static
    make
    make check
    make docdir=/usr/share/doc/check-0.15.2 install
}

install_diffutils() {
    cd /sources/diffutils-3.10
    ./configure --prefix=/usr
    make
    make check
    make install
}

install_gawk() {
    cd /sources/gawk-5.3.0
    sed -i 's/extras//' Makefile.in
    ./configure --prefix=/usr
    make
    chown -R tester .
    su tester -c "PATH=$PATH make check"
    rm -f /usr/bin/gawk-5.3.1
    make install
    ln -sv gawk.1 /usr/share/man/man1/awk.1
    install -vDm644 doc/{awkforai.txt,*.{eps,pdf,jpg}} -t /usr/share/doc/gawk-5.3.1
}

installing_basic_system() {
# TODO: descomentar en la versión final.
    ##package_management
    #install_man_pages
    #install_iana_etc
    #install_glibc
    #install_zlib
    #install_bzip
    #install_xz
    #install_lz4
    #install_zstd
    #install_file
    #install_readline
    #install_m4
    #install_bc
    #install_flex
    #install_tcl
    #install_spect
    #install_dejaGNU
    #install_pkgconf
    #install_binutils
    #install_gmp
    #install_mpfr
    #install_mpc
    #install_attr
    #install_acl
    #install_libcap
    #install_libxcrypt
    #install_shadow
    #install_gcc
    #install_ncurses
    #install_sed
    #install_psmisc
    #install_gettext
    #install_bison
    #install_grep
    #install_bash
    #install_libtool
    #install_gdbm
    #install_gperf
    #install_expat
    #install_inetutils
    #install_less
    #install_perl
    #install_xml_parser
    #install_intltool
    #install_autoconf
    #install_automake
    #install_openssl
    #install_kmod
    #install_libelf_from_elfutils
    #install_libffi
    #install_python
    #install_flitcore
    #install_whell
    #install_setuptools
    install_ninja
    install_meson
    install_coreutils
    install_check
    install_diffutils


    
    }

# Función para continuar con la construcción del sistema base
builddist() {
#TODO: descomentar en la versión final.
    #touch /var/log/{btmp,lastlog,faillog,wtmp}
    #chgrp -v utmp /var/log/lastlog
    #chmod -v 664  /var/log/lastlog
    #chmod -v 600  /var/log/btmp

    #build_gettext
    #build_bison
    #build_perl
    #build_python
    #build_texinfo
    #build_util_linux
    #cleaning_and_backup

    installing_basic_system    

}

# Función principal
main() {
    check_root

    if [ "$ACTION" == "buildtools" ]; then
        buildtools
    elif [ "$ACTION" == "buildbase" ]; then
        buildbase
    elif [ "$ACTION" == "builddist" ]; then
        builddist        
    else
        echo "Acción no válida: $ACTION"
        usage
    fi
}

# Process arguments
if [[ $# -lt 1 ]]; then
    usage
fi

ACTION="$1"
shift

clear
echo "Linux From Scratch Automation Script"
echo "Fegor's Creation Distribution for Linux"
echo ""

while getopts "p:u:v:h" opt; do
    case "$opt" in
        p) INSTALL_PATH="$OPTARG" ;;
        u) LFS_USER="$OPTARG" ;;
        v) LFS_VERSION="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Validar parámetros requeridos
if [[ -z "$ACTION" || ( "$ACTION" != "buildtools" && "$ACTION" != "buildbase" && "$ACTION" != "builddist") ]]; then
    echo "Error: La primera opción debe ser 'buildtools', 'buildbase' o 'builddist'."
    usage
fi

if [[ -z "$INSTALL_PATH" || -z "$LFS_USER" ]]; then
    echo "Error: path de instalación y usuario son requeridos."
    usage
fi

# Ejecutar el script principal
main | tee $LOG_FILE
