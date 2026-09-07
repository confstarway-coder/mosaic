#!/bin/sh
copy() {
        echo "Warning: wasm-opt not found or failed, just copying module"

        local dst=""
        while getopts ':o:' opt; do
                case $opt in
                        o) dst="$OPTARG" ;;
                        *) ;;
                esac
        done
        shift $(($OPTIND - 1))
        local src="$1"

        cp -v "$src" "$dst"
}

if command -v wasm-opt >/dev/null; then
        wasm-opt "$@" 2>/dev/null || copy "$@"
else
        copy "$@"
fi

exit 0
