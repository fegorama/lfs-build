#!/bin/sh
# Begin checkman.sh
# Usage: find /usr/share/man -type f | xargs checkman.sh
for a in "$@"
do
    # echo "Checking $a..."
    # Pure-ASCII manual page (possibly except comments) is OK
    grep -v '.\\"' "$a" | iconv -f US-ASCII -t US-ASCII >/dev/null 2>&1 \
        && continue
    # Non-UTF-8 manual page is OK
    iconv -f UTF-8 -t UTF-8 "$a" >/dev/null 2>&1 || continue
    # Found a UTF-8 manual page, bad.
    echo "UTF-8 manual page: $a" >&2
done
# End checkman.sh
