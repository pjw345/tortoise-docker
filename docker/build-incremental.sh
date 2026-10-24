#!/usr/bin/env bash
set -euo pipefail

[[ ${SOURCE_COMMIT:-} =~ ^[0-9a-f]{40}$ ]] || { echo 'A full source SHA is required.' >&2; exit 1; }
[[ ${CPU_TARGET:-} =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Invalid CPU target.' >&2; exit 1; }
[[ ${BUILD_JOBS:-} =~ ^[1-9][0-9]*$ ]] || { echo 'Invalid build job count.' >&2; exit 1; }

export CCACHE_DIR=/native-cache/ccache
export CCACHE_MAXSIZE=3G
mkdir -p /native-cache/source
cd /native-cache/source
if [[ ! -d .git ]]; then
    git init .
fi
# Fetch objects from the read-only Ubuntu checkout, not from GitHub. A separate
# cached checkout lets explicit older revisions build without changing that tree.
# The bind context retains the host UID. Trust it inside this isolated builder;
# upload-pack/submodule child processes need the setting too, not just git -c.
git config --global --add safe.directory '*'
git fetch --no-tags /local-core "$SOURCE_COMMIT"

# Keep the patched CMake file's timestamp when its effective contents are equal.
# Otherwise restoring the portability patch would reconfigure every warm build.
previous=/native-cache/previous-CMakeLists.txt
if [[ -f CMakeLists.txt ]]; then cp -p CMakeLists.txt "$previous"; fi
if git rev-parse --verify HEAD >/dev/null 2>&1; then
    git restore CMakeLists.txt
fi
git checkout --detach FETCH_HEAD
[[ $(git rev-parse HEAD) == "$SOURCE_COMMIT" ]]
git submodule init
while read -r key path; do
    name=${key#submodule.}
    name=${name%.path}
    git config "submodule.$name.url" "/local-core/$path"
done < <(git config -f .gitmodules --get-regexp '^submodule\..*\.path$')
git -c protocol.file.allow=always -c safe.directory='*' submodule update --init --recursive
sed -i "s/-march=native/-march=${CPU_TARGET}/g" CMakeLists.txt
if [[ -f $previous ]] && cmp -s "$previous" CMakeLists.txt; then
    cp -p "$previous" CMakeLists.txt
fi

# One build tree, not a tree per commit. Make/CMake retain unchanged object files;
# ccache covers files rebuilt after a header/toolchain change or branch switch.
ccache --zero-stats
cmake -S . -B /native-cache/build \
    -DCMAKE_BUILD_TYPE="$CMAKE_BUILD_TYPE" \
    -DCMAKE_INSTALL_PREFIX="$CMAKE_INSTALL_PREFIX" \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    -DBUILD_PLAYERBOTS="$BUILD_PLAYERBOTS" -DUSE_EXTRACTORS="$USE_EXTRACTORS" \
    -DALLOW_TURTLE_ADDONS=ON -DBUILD_ELUNA_TESTS=OFF -DENABLE_SOAP=ON
cmake --build /native-cache/build -j"$BUILD_JOBS"
cmake --install /native-cache/build
ccache --show-stats
printf '%s\n' "$SOURCE_COMMIT" > /opt/turtle/SOURCE_COMMIT

# Stage SQL from this exact checkout into the image, not the persistent cache.
mkdir -p /opt/turtle/sql/database_updates/character
cp -a sql/create_databases.sql sql/base sql/database_updates /opt/turtle/sql/
cp -a sql/character_updates/. /opt/turtle/sql/database_updates/character/
if [[ $BUILD_PLAYERBOTS == ON ]]; then
    if [[ -d modules/mod-playerbots/sql ]]; then
        mkdir -p /opt/turtle/sql/playerbots
        cp -a modules/mod-playerbots/sql/. /opt/turtle/sql/playerbots/
    elif [[ -d src/modules/PlayerBots/sql ]]; then
        mkdir -p /opt/turtle/sql/playerbots
        cp -a src/modules/PlayerBots/sql/. /opt/turtle/sql/playerbots/
    else
        echo 'Playerbots SQL missing.' >&2
        exit 1
    fi
fi
