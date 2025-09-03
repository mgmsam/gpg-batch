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
    "$GPG" $GPG_OPTIONS "$@" <<BATCH
$BATCH
BATCH
}

gpg_generate_key ()
{
    BATCH="$KEY"
    KEY_ID="$(run_gpg --full-gen-key)"
    KEY_ID="${KEY_ID##*"$LF"}"
    KEY_ID="${KEY_ID##*[[:blank:]]}"
    RETURN=0
    CREATED_KEY_ID="${CREATED_KEY_ID:+"$CREATED_KEY_ID "}$KEY_ID"
}

gpg_addkey ()
{
    run_gpg --command-fd=0 --pinentry-mode=loopback --edit-key "$KEY_ID"
    RETURN=0
}

parse_keyword ()
{
    IFS="$IFS,"
    set -- $1
    while test $# -gt 0
    do
        case "$1" in
            auth)
                AUTH=auth
                ;;
            cert)
                ;;
            encrypt)
                ENCRYPT=encrypt
                ;;
            sign)
                SIGN=sign
        esac
        shift
    done
    echo ${AUTH:-} ${ENCRYPT:-} ${SIGN:-}
}

get_subkey ()
{
    SUBKEY_TYPE=
    SUBKEY_LENGTH=
    SUBKEY_CURVE=
    SUBKEY_USAGE=
    while read -r KEYWORD || test "${KEYWORD:-}"
    do
        case "$KEYWORD" in
            Subkey-Type:*)
                test -z "${SUBKEY_TYPE:-}" || return 0
                SUBKEY_TYPE="${KEYWORD#Subkey-Type:}"
                SUBKEY_TYPE="${SUBKEY_TYPE#"${SUBKEY_TYPE%%[![:blank:]]*}"}"
                ;;
            Subkey-Length:*)
                case "${SUBKEY_TYPE:-}" in
                    [eE][cC][cC]|[eE][cC][dD][hH]|[eE][cCdD][dD][sS][aA])
                        return
                esac
                test -z "${SUBKEY_LENGTH:-}" || return 0
                SUBKEY_LENGTH="${KEYWORD#Subkey-Length:}"
                SUBKEY_LENGTH="${SUBKEY_LENGTH#"${SUBKEY_LENGTH%%[![:blank:]]*}"}"
                ;;
            Subkey-Curve:*)
                case "${SUBKEY_TYPE:-}" in
                    [dDrR][sS][aA]|[eE][lL][gG])
                        return
                esac
                test -z "${SUBKEY_CURVE:-}" || return 0
                SUBKEY_CURVE="${KEYWORD#Subkey-Curve:}"
                SUBKEY_CURVE="${SUBKEY_CURVE#"${SUBKEY_CURVE%%[![:blank:]]*}"}"
                ;;
            Subkey-Usage:*)
                test -z "${SUBKEY_USAGE:-}" || return 0
                SUBKEY_USAGE="${KEYWORD#Subkey-Usage:}"
                SUBKEY_USAGE="${SUBKEY_USAGE#"${SUBKEY_USAGE%%[![:blank:]]*}"}"
                SUBKEY_USAGE="$(parse_keyword "$SUBKEY_USAGE")"
                ;;
        esac
        SUBKEY="${SUBKEY#"$KEYWORD"}"
        SUBKEY="${SUBKEY#"$LF"}"
    done <<BATCH
$SUBKEY
BATCH
}

build_batch ()
{
    case "${SUBKEY_TYPE:-}" in
        "")
            return 1
            ;;
        [dD][sS][aA])
            case "${SUBKEY_USAGE:-}" in
                ""|"auth sign")
                    BATCH="7${LF}A${LF}Q$LF"
                    ;;
                auth)
                    BATCH="7${LF}S${LF}A${LF}Q$LF"
                    ;;
                sign)
                    BATCH="3$LF"
            esac
            ;;
        ELG)
            case "${SUBKEY_USAGE:-}" in
                ""|*encrypt*)
                    BATCH="5$LF"
            esac
            ;;
        [rR][sS][aA])
            case "${SUBKEY_USAGE:-}" in
                ""|"auth encrypt sign")
                    BATCH="8${LF}A${LF}Q$LF"
                    ;;
                "auth sign")
                    BATCH="8${LF}E${LF}A${LF}Q$LF"
                    ;;
                "auth encrypt")
                    BATCH="8${LF}S${LF}A${LF}Q$LF"
                    ;;
                "encrypt sign")
                    BATCH="8${LF}Q$LF"
                    ;;
                auth)
                    BATCH="8${LF}S${LF}E${LF}A${LF}Q$LF"
                    ;;
                encrypt)
                    BATCH="6$LF"
                    ;;
                sign)
                    BATCH="4$LF"
                    ;;
            esac
            ;;
    esac
    BATCH="addkey$LF$BATCH${SUBKEY_LENGTH:-}$LF$EXPIRE_DATE${LF}y${LF}save"
}

gpg_generate_subkey ()
{
    while test "${SUBKEY:-}"
    do
        get_subkey
        build_batch || continue
        gpg_addkey
    done
}

set_batch_vars ()
{
    KEY=
    SUBKEY=
    SUBKEY_COUNT=
    EXPIRE_DATE=
    PASSPHRASE=
}

run_batch ()
{
    case "${KEY:-}" in
        ?*)
            case "${SUBKEY_COUNT:-}" in
                ""|1)
                    KEY="$KEY$LF$SUBKEY"
                    gpg_generate_key
                    ;;
                *)
                    gpg_generate_key
                    gpg_generate_subkey
            esac
            ;;
        *)
            case "${SUBKEY_COUNT:-}" in
                ?*)
                    gpg_generate_subkey
                    ;;
            esac
    esac
    set_batch_vars
}

run_batch_file ()
{
    RETURN=1
    set_batch_vars
    while read -r KEYWORD || test "${KEYWORD:-}"
    do
        case "${KEYWORD:-}" in
            ""|[#\;]*)
                continue
                ;;
            %commit)
                run_batch
                continue
                ;;
            "Expire-Date: "*)
                EXPIRE_DATE="${KEYWORD##*[[:blank:]]}"
                ;;
            "Passphrase:"*)
                PASSPHRASE="${KEYWORD#Passphrase:}"
                PASSPHRASE="${PASSPHRASE#"${PASSPHRASE%%[![:blank:]]*}"}"
                ;;
            "Subkey-Type: "*)
                SUBKEY="${SUBKEY:+"$SUBKEY$LF"}$KEYWORD"
                SUBKEY_COUNT="$((SUBKEY_COUNT + 1))"
                continue
                ;;
            "Subkey-"*)
                SUBKEY="${SUBKEY:+"$SUBKEY$LF"}$KEYWORD"
                continue
        esac
        KEY="${KEY:+"$KEY$LF"}$KEYWORD"
    done < "$1"
    test "${KEY:-"${SUBKEY:-}"}" || return "$RETURN"
    run_batch
    test -z "${CREATED_KEY_ID:-}" || say "key created: $CREATED_KEY_ID"
}

main ()
{
    PKG="${0##*/}"
    GPG="$(which gpg)" || die "gpg: command not found"
    GPG_OPTIONS="--batch --expert --verbose --status-fd=1"
    LF='
'

    for BATCH in "$@"
    do
        run_batch_file "$BATCH"
    done
    return "$RETURN"
}

main "$@"
