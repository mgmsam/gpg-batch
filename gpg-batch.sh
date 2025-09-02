#!/bin/sh
# gpg-batch. Unattended key generation.
#
# Copyright (c) 2025 Semyon A Mironov
#
# Authors: Semyon A Mironov <s.mironov@mgmsam.pro>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

if test "${KSH_VERSION:-}"
then
    PUTS=print
    puts ()
    {
        print "${PUTS_OPTIONS:--r}" -- "$*"
    }
else
    if type printf >/dev/null 2>&1
    then
        PUTS=printf
        puts ()
        {
            printf "${PUTS_OPTIONS:-%s\n}" "$*"
        }
    elif type echo >/dev/null 2>&1
    then
        PUTS=echo
        puts ()
        {
            echo "${PUTS_OPTIONS:-}" "$*"
        }
    else
        exit 1
    fi
fi

say ()
{
    RETURN=$?
    PUTS_OPTIONS=
    while test $# -gt 0
    do
        case "${1:-}" in
            -n)
                test "$PUTS" = printf &&
                PUTS_OPTIONS=%s ||
                PUTS_OPTIONS=-n
                ;;
            *[!0-9]*|"")
                break
                ;;
            *)
                RETURN=$1
        esac
        shift
    done
    case "$@" in
        ?*)
            puts "$PKG:${1:+" $@"}"
            PUTS_OPTIONS=
    esac
}

die ()
{
    say "$@" >&2
    exit "$RETURN"
}

which ()
{
    case "${PATH:-}" in
        *[!:]:)
            PATH="$PATH:"
            ;;
    esac
    RETURN=1
    case "${1:-}" in
        */*)
            if  test -f "$1" &&
                test -x "$1"
            then
                puts "$1"
                RETURN=0
            fi
            ;;
        ?*)
            IFS_SAVE="${IFS:-}"
            IFS=:
            for ELEMENT in $PATH
            do
                test "${ELEMENT:-}" || ELEMENT=.
                if  test -f "$ELEMENT/$1" &&
                    test -x "$ELEMENT/$1"
                then
                    puts "$ELEMENT/$1"
                    RETURN=0
                    break
                fi
            done
            IFS="${IFS_SAVE:-}"
    esac
    return "$RETURN"
}

run_gpg ()
{
    "$GPG" $GPG_OPTIONS "$1" <<BATCH
$BATCH
BATCH
}

gpg_generatekey ()
{
    BATCH="$OPTIONS_KEY"
    KEY_ID="$(run_gpg --full-gen-key)"
    KEY_ID="${KEY_ID##*"$LF"}"
    KEY_ID="${KEY_ID##*[[:blank:]]}"
    RETURN=0
    CREATED_KEY_ID="${CREATED_KEY_ID:+"$CREATED_KEY_ID "}$KEY_ID"
}

gpg_addkey ()
{
    BATCH="$OPTIONS_SUBKEY"
    {
        echo addkey
        echo "$BATCH"
        echo "$EXPIRE_DATE"
        echo "$PASSPHRASE"
        echo save
    } | run_gpg --edit-key "$KEY_ID"
    RETURN=0
    say "subkey created: $KEY_ID"
}

set_batch_vars ()
{
    OPTIONS_KEY=
    OPTIONS_SUBKEY=
    SUBKEY_COUNT=
    EXPIRE_DATE=
    PASSPHRASE=
}

run_batch ()
{
    case "${OPTIONS_KEY:-}" in
        ?*)
            case "${SUBKEY_COUNT:-}" in
                ""|1)
                    OPTIONS_KEY="$OPTIONS_KEY$LF$OPTIONS_SUBKEY"
                    gpg_generatekey
                    ;;
                *)
                    gpg_generatekey
                    gpg_addkey
            esac
            ;;
        *)
            case "${SUBKEY_COUNT:-}" in
                ?*)
                    gpg_addkey
                    ;;
            esac
    esac
    set_batch_vars
}

run_batch_file ()
{
    RETURN=1
    set_batch_vars
    while read -r OPTION || test "${OPTION:-}"
    do
        case "${OPTION:-}" in
            ""|[#\;]*)
                continue
                ;;
            %commit)
                run_batch
                continue
                ;;
            "Expire-Date: "*)
                EXPIRE_DATE="${OPTION##*[[:blank:]]}"
                ;;
            "Passphrase: "*)
                PASSPHRASE="${OPTION##*[[:blank:]]}"
                ;;
            "Subkey-Type: "*)
                OPTIONS_SUBKEY="${OPTIONS_SUBKEY:+"$OPTIONS_SUBKEY$LF"}$OPTION"
                SUBKEY_COUNT="$((SUBKEY_COUNT + 1))"
                continue
                ;;
            "Subkey-"*)
                OPTIONS_SUBKEY="${OPTIONS_SUBKEY:+"$OPTIONS_SUBKEY$LF"}$OPTION"
                continue
        esac
        OPTIONS_KEY="${OPTIONS_KEY:+"$OPTIONS_KEY$LF"}$OPTION"
    done < "$1"
    test "${OPTIONS_KEY:-"${OPTIONS_SUBKEY:-}"}" || return "$RETURN"
    run_batch
    test -z "${CREATED_KEY_ID:-}" || say "key created: $CREATED_KEY_ID"
}

main ()
{
    PKG="${0##*/}"
    GPG="$(which gpg)" || die "gpg: command not found"
    GPG_OPTIONS="--batch --expert --command-fd=0 --status-fd=1 --pinentry-mode=loopback --verbose"
    LF='
'

    for BATCH in "$@"
    do
        run_batch_file "$BATCH"
    done
    return "$RETURN"
}

main "$@"
