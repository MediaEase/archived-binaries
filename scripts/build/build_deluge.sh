#!/usr/bin/env bash
set -e

# =============================================================================
# build_deluge.sh
#
# Ce script compile et package Deluge selon trois variantes :
#
#   - oldstable : Deluge (tag 2.1.1) avec libtorrent 1.2.x (tag v1.2.20)
#   - stable    : Deluge (tag 2.1.1) avec libtorrent 2.0.11 (tag v2.0.11)
#   - next      : Deluge (branche develop) avec libtorrent (branche RC_2_0)
#
# Le package final (.deb) sera installé dans :
#   /opt/MediaEase/.binaries/installed/deluge-<variant>_<deluge_version>/
#
# Un fichier .env sera créé à la racine de cette installation pour faciliter
# le switch entre les versions.
#
# IMPORTANT : La compilation de libtorrent est réalisée avec Ninja et en mode
# statique (option -DBUILD_SHARED_LIBS=OFF) avec les options static_runtime,
# build_tools et python-bindings activées.
#
# Le nom final du package inclut le numéro de build, par exemple :
#   deluge-stable_2.1.1-1build1_lt_2.0.11_amd64.deb
#
# Usage:
#   ./build_deluge.sh <variant>
# Exemples:
#   ./build_deluge.sh oldstable
#   ./build_deluge.sh stable
#   ./build_deluge.sh next
# =============================================================================

usage() {
    echo "Usage: $0 <variant>"
    echo "Variants disponibles: oldstable, stable, next"
    exit 1
}

if [ $# -ne 1 ]; then
    usage
fi
VARIANT="$1"
echo "==> Compilation de Deluge en mode '$VARIANT'"
case "$VARIANT" in
    oldstable)
        DELUGE_REF="2.1.1"
        LIBTORRENT_REF="v1.2.20"
        INSTALL_TAG="deluge-oldstable"
        ;;
    stable)
        DELUGE_REF="2.1.1"
        LIBTORRENT_REF="v2.0.11"
        INSTALL_TAG="deluge-stable"
        ;;
    next)
        DELUGE_REF="develop"
        LIBTORRENT_REF="RC_2_0"
        INSTALL_TAG="deluge-next"
        ;;
    *)
        echo "ERREUR : Variante '$VARIANT' non reconnue. Choisissez parmi oldstable, stable, next."
        exit 1
        ;;
esac
if [[ "$DELUGE_REF" != *"-"* ]]; then
    PACKAGE_VERSION="${DELUGE_REF}-1build1"
else
    PACKAGE_VERSION="$DELUGE_REF"
fi
LIBTORRENT_VER="${LIBTORRENT_REF#v}"
WORKDIR="$PWD/build_deluge"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
INSTALL_DIR="$PWD/custom_build/pkg_deluge"
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/libtorrent"
mkdir -p "$INSTALL_DIR/deluge"

##########################
# 0. Compilation de Boost 1.87.0_rc1
##########################
# echo "==> Téléchargement et compilation de Boost 1.87.0_rc1..."
# BOOST_VERSION="1_87_0_rc1"
# BOOST_URL="https://archives.boost.io/release/1.87.0/source/boost_${BOOST_VERSION}.tar.gz"
# BOOST_TAR="boost_${BOOST_VERSION}.tar.gz"
# BOOST_DIR="boost_${BOOST_VERSION%_rc1}"
# mkdir -p "$PWD/dist"
# if [ ! -f "$PWD/dist/$BOOST_TAR" ]; then
#     wget -O "$PWD/dist/$BOOST_TAR" "$BOOST_URL"
# fi
# [[ -d "$WORKDIR/$BOOST_DIR" ]] && rm -rf "$WORKDIR/$BOOST_DIR"
# tar -xzf "$PWD/dist/$BOOST_TAR" -C "$WORKDIR"
# cd "$WORKDIR/$BOOST_DIR"
# ./bootstrap.sh --prefix=/usr/local
# ./b2 install
# cd "$WORKDIR"

##########################
# 1. Compilation de libtorrent (mode statique)
##########################
echo "==> Clonage et compilation de libtorrent ($LIBTORRENT_REF) en mode statique..."
cd "$WORKDIR"
rm -rf libtorrent
git clone --depth 1 --branch "$LIBTORRENT_REF" https://github.com/arvidn/libtorrent.git libtorrent
cd libtorrent
echo "Utilisation de libtorrent : $LIBTORRENT_REF"
if [[ "$LIBTORRENT_REF" == "RC_"* ]]; then
    LIBTORRENT_VER=$(grep -oP '#define LIBTORRENT_VERSION "\K[0-9.]+(?=\.\d+)' include/libtorrent/version.hpp)
fi
mkdir -p build && cd build
cmake -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_STANDARD=14 \
    -G Ninja \
    -Dstatic_runtime=ON \
    -Dbuild_tools=ON \
    -Dpython-bindings=ON \
    -Dbuild_tests=OFF \
    -Dbuild_examples=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR/libtorrent" \
    ..
ninja
cmake --install .
cd "$WORKDIR"
export LIBTORRENT_VER

##########################
# 2. Compilation de Deluge
##########################
echo "==> Clonage et compilation de Deluge ($DELUGE_REF)..."
cd "$WORKDIR"
rm -rf deluge
git clone --depth 1 --branch "$DELUGE_REF" https://github.com/deluge-torrent/deluge.git deluge
cd deluge
echo "Utilisation de Deluge : $DELUGE_REF"
uv venv
source .venv/bin/activate
uv pip install --upgrade pip setuptools
uv pip install cython twisted pyOpenSSL rencode PyXDG zope.interface setproctitle Pillow dbus-python ifaddr mako
python setup.py build
python setup.py install --prefix="$INSTALL_DIR/deluge"
deactivate
# read the version from the deluge RELEASE-VERSION file
VERSION_FILE="$WORKDIR/deluge/RELEASE-VERSION"
if [ -f "$VERSION_FILE" ]; then
    PACKAGE_VERSION=$(cat "$VERSION_FILE")
else
    echo "ERREUR : Le fichier RELEASE-VERSION n'a pas été trouvé."
    exit 1
fi
cd "$WORKDIR"

##########################
# 3. Assemblage de l'installation finale
##########################
FINAL_INSTALL="/opt/MediaEase/.binaries/installed/${INSTALL_TAG}_${PACKAGE_VERSION}"
echo "==> Assemblage de l'installation finale dans '$FINAL_INSTALL'"
PKG_DIR="$WORKDIR/pkg_deluge"
rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR/DEBIAN"
mkdir -p "$PKG_DIR$FINAL_INSTALL"
cp -r "$INSTALL_DIR/libtorrent/" "$PKG_DIR$FINAL_INSTALL/"
cp -r "$INSTALL_DIR/deluge/" "$PKG_DIR$FINAL_INSTALL/"

##########################
# 4. Préparation du package Debian
##########################
echo "==> Préparation du package Debian pour Deluge..."
runtime_size=$(du -s -k "$PKG_DIR$FINAL_INSTALL" | cut -f1)
cat <<EOF > "$PKG_DIR/DEBIAN/control"
Package: ${INSTALL_TAG}
Version: ${PACKAGE_VERSION}
Architecture: amd64
Maintainer: VotreNom <votre.email@example.com>
Installed-Size: $runtime_size
Depends: python3, libtorrent
Section: net
Priority: optional
Homepage: https://deluge-torrent.org
Description: Deluge ${DELUGE_REF} compilé avec libtorrent ${LIBTORRENT_VER} en binaire statique.
 Deluge est un client BitTorrent léger. Ce package inclut également la version de
 libtorrent utilisée pour la compilation.
EOF

# Création du script postinst (adapté de rtorrent)
cat <<'EOF' > "$PKG_DIR/DEBIAN/postinst"
#!/bin/sh
set -e
case "$1" in
    configure)
        PKG_NAME="${DPKG_MAINTSCRIPT_PACKAGE}"
        PKG_VERSION="$(dpkg-query -W -f='${Version}' "${PKG_NAME}")"
        BASE_VERSION="${PKG_VERSION%-*}"
        INSTALL_BASE="/opt/MediaEase/.binaries/installed/${PKG_NAME}_${BASE_VERSION}"
        ENV_FILE="${INSTALL_BASE}/.env"
        case "${PKG_NAME}" in
        *-next)
            PRIORITY=60
            ;;
        *-oldstable)
            PRIORITY=40
            ;;
        *-stable)
            PRIORITY=50
            ;;
        *)
            PRIORITY=40
            ;;
        esac
        cat > "${ENV_FILE}" <<EOF2
export CPATH="${INSTALL_BASE}/include:\$CPATH"
export C_INCLUDE_PATH="${INSTALL_BASE}/include:\$C_INCLUDE_PATH"
export CPLUS_INCLUDE_PATH="${INSTALL_BASE}/include:\$CPLUS_INCLUDE_PATH"
export LIBRARY_PATH="${INSTALL_BASE}/lib:\$LIBRARY_PATH"
export LD_LIBRARY_PATH="${INSTALL_BASE}/lib:\$LD_LIBRARY_PATH"
export PKG_CONFIG_PATH="${INSTALL_BASE}/lib/pkgconfig:\$PKG_CONFIG_PATH"
export PATH="${INSTALL_BASE}/bin:\$PATH"
EOF2
        if command -v mandb >/dev/null 2>&1; then
            mandb || true
        fi
    ;;
    abort-upgrade|abort-install|abort-remove)
    ;;
    *)
    ;;
esac
exit 0
EOF

# Création du script prerm (adapté de rtorrent)
cat <<'EOF' > "$PKG_DIR/DEBIAN/prerm"
#!/bin/sh
set -e
case "$1" in
    remove|deconfigure)
        PKG_NAME="${DPKG_MAINTSCRIPT_PACKAGE}"
        PKG_VERSION="$(dpkg-query -W -f='${Version}' "${PKG_NAME}")"
        BASE_VERSION="${PKG_VERSION%-*}"
        INSTALL_BASE="/opt/MediaEase/.binaries/installed/${PKG_NAME}_${BASE_VERSION}"
        if [ -f "${INSTALL_BASE}/.env" ]; then
            rm -f "${INSTALL_BASE}/.env"
        fi
    ;;
    upgrade|failed-upgrade|abort-install|abort-upgrade|disappear)
    ;;
    *)
        echo "prerm called with an unknown argument \`$1\`" >&2
        exit 1
    ;;
esac
exit 0
EOF

chmod 755 "$PKG_DIR/DEBIAN/postinst" "$PKG_DIR/DEBIAN/prerm"

echo "==> Génération du fichier md5sums..."
(cd "$PKG_DIR"; find . -type f ! -path "./DEBIAN/*" -exec md5sum {} \; > DEBIAN/md5sums)
DEB_NAME="deluge-${INSTALL_TAG}_${PACKAGE_VERSION}_lt_${LIBTORRENT_VER}_amd64.deb"
echo "==> Création du package Debian : $DEB_NAME"
dpkg-deb --build -Zxz -z9 --root-owner-group "$PKG_DIR" "$DEB_NAME"
echo "==> Package construit avec succès : $DEB_NAME"
echo "==> Installation terminée. Vous pouvez maintenant installer le package avec :"
echo "sudo dpkg -i $DEB_NAME"
echo "==> N'oubliez pas de vérifier les dépendances et de les installer si nécessaire."
echo "==> Fin du script de compilation de Deluge."
echo "==> Merci d'avoir utilisé ce script !"
