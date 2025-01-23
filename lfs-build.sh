#!/bin/bash

# Linux From Scratch Automation Script
# Fegor's Creation Distribution for Linux

set -e

# Variables globales
INSTALL_PATH="/lfs"
LFS_USER="lfs"
LFS_VERSION="12.2"  # Cambia según la versión de LFS
LOG_FILE="lfs-build.log"

# Función para mostrar ayuda
usage() {
    echo "Uso: $0 -p <path_instalacion> -u <usuario> [-v <version>] [-h]"
    echo "  -p    Path donde se instalará LFS"
    echo "  -u    Usuario para la instalación inicial (primera fase) - se recomienda usar lfs"
    echo "  -v    Versión de Linux From Scratch (por defecto: $LFS_VERSION)"
    echo "  -h    Mostrar esta ayuda"
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
    echo "Descargando fuentes..."
    wget --continue --no-clobber --input-file=./wget-list-sysv --continue --directory-prefix=$LFS/sources
    cp ./md5sums $LFS/sources
    pushd $LFS/sources
        md5sum -c md5sums
    popd
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
    #temp_binutils_pass1
    #temp_gcc_pass1
    #temp_linux_api_headers
    #temp_gclib
    #temp_libstdcxx
    #temp_m4
    #temp_ncurses
    #temp_bash
    #temp_coreutils
    #temp_diffutils
    #temp_file
    #temp_findutils
    #temp_gawk
    #temp_grep
    #temp_gzip
    #temp_make
    #temp_patch
    #temp_sed
    #temp_tar
    #temp_xz
    #temp_binutils_pass2
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
make tooldir=/usr && make tooldir=/usr install
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

# Función para construir el sistema base
build_base_system() {
    echo "Construyendo el sistema base..."
    # Aquí incluirías los pasos para construir el sistema base según el libro LFS.
}

# Función para configurar el sistema
configure_system() {
    echo "Configurando el sistema..."
    # Incluye comandos para configurar los scripts de arranque, kernel, etc.
}

# Función principal
main() {
    check_root
    initialize
    check_dependencies
    download_sources
    prepare_environment
    build_temporary_tools
    build_base_system
    configure_system
    echo "Instalación completada. Revisa el log en $LOG_FILE para más detalles."
}

# Procesar argumentos
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
if [[ -z "$INSTALL_PATH" || -z "$LFS_USER" ]]; then
    echo "Error: path de instalación y usuario son requeridos."
    usage
fi

# Ejecutar el script principal
main | tee $LOG_FILE
