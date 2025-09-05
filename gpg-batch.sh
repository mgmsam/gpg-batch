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
    if KEY_ID="$(run_gpg --full-gen-key "$@")"
    then
        test "${DRY_RUN:-}" || {
            KEY_ID="${KEY_ID##*"$LF"}"
            KEY_ID="${KEY_ID##*[[:blank:]]}"
            CREATED_KEY_ID="${CREATED_KEY_ID:+"$CREATED_KEY_ID "}$KEY_ID"
        }
    else
        return $?
    fi
}

gpg_addkey ()
{
    run_gpg --command-fd=0 --pinentry-mode=loopback --edit-key "$KEY_ID"
}

parse_usage ()
{
    IFS="$IFS,"
    set -- $SUBKEY_USAGE
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

parse_curve ()
{
    case "${SUBKEY_CURVE:-}" in
        cv25519)
            echo 0
        ;;
        ed25519)
            echo 1
        ;;
        ed448)
            echo 2
        ;;
        nistp256)
            echo 3
        ;;
        nistp384)
            echo 4
        ;;
        nistp521)
            echo 5
        ;;
        brainpoolP256r1)
            echo 6
        ;;
        brainpoolP384r1)
            echo 7
        ;;
        brainpoolP512r1)
            echo 8
        ;;
        secp256k1)
            echo 9
        ;;
    esac
}

get_subkey ()
{
    SUBKEY_TYPE=
    SUBKEY_LENGTH=
    SUBKEY_CURVE=
    SUBKEY_USAGE=
    while read -r SUBKEYWORD || test "${SUBKEYWORD:-}"
    do
        case "$SUBKEYWORD" in
            Subkey-Type:*)
                test -z "${SUBKEY_TYPE:-}" || return 0
                SUBKEY_TYPE="${SUBKEYWORD#Subkey-Type:}"
                SUBKEY_TYPE="${SUBKEY_TYPE#"${SUBKEY_TYPE%%[![:blank:]]*}"}"
                ;;
            Subkey-Length:*)
                case "${SUBKEY_TYPE:-}" in
                    [eE][cC][cC]|[eE][cC][dD][hH]|[eE][cCdD][dD][sS][aA])
                        return
                esac
                test -z "${SUBKEY_LENGTH:-}" || return 0
                SUBKEY_LENGTH="${SUBKEYWORD#Subkey-Length:}"
                SUBKEY_LENGTH="${SUBKEY_LENGTH#"${SUBKEY_LENGTH%%[![:blank:]]*}"}"
                ;;
            Subkey-Curve:*)
                case "${SUBKEY_TYPE:-}" in
                    [dDrR][sS][aA]|[eE][lL][gG])
                        return
                esac
                test -z "${SUBKEY_CURVE:-}" || return 0
                SUBKEY_CURVE="${SUBKEYWORD#Subkey-Curve:}"
                SUBKEY_CURVE="${SUBKEY_CURVE#"${SUBKEY_CURVE%%[![:blank:]]*}"}"
                SUBKEY_CURVE="$(parse_curve)"
                ;;
            Subkey-Usage:*)
                test -z "${SUBKEY_USAGE:-}" || return 0
                SUBKEY_USAGE="${SUBKEYWORD#Subkey-Usage:}"
                SUBKEY_USAGE="$(parse_usage)"
                ;;
        esac
        SUBKEY="${SUBKEY#"$SUBKEYWORD"}"
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
        1 | [rR][sS][aA])
            case "${SUBKEY_USAGE:-}" in
                "" | "auth encrypt sign")
                    BATCH="8${LF}A${LF}Q"
                ;;
                "auth sign")
                    BATCH="8${LF}E${LF}A${LF}Q"
                ;;
                "auth encrypt")
                    BATCH="8${LF}S${LF}A${LF}Q"
                ;;
                "encrypt sign")
                    BATCH="8${LF}Q"
                ;;
                auth)
                    BATCH="8${LF}S${LF}E${LF}A${LF}Q"
                ;;
                encrypt)
                    BATCH=6
                ;;
                sign)
                    BATCH=4
                ;;
            esac
        ;;
        16 | ELG | ELG-E)
            BATCH=5
        ;;
        17 | [dD][sS][aA])
            case "${SUBKEY_USAGE:-}" in
                "" | "auth sign")
                    BATCH="7${LF}A${LF}Q"
                ;;
                auth)
                    BATCH="7${LF}S${LF}A${LF}Q"
                ;;
                sign)
                    BATCH=3
                ;;
            esac
        ;;
        18 | [eE][cC][cC] | [eE][cC][dD][hH])
            case "${SUBKEY_CURVE:-}" in
                0)
                    BATCH="12${LF}1"
                ;;
                [1-9]*)
                    BATCH="12${LF}$SUBKEY_CURVE"
                ;;
            esac
        ;;
        19 | 22 | [eE][cCdD][dD][sS][aA])
            case "${SUBKEY_USAGE:-}" in
                "" | "auth sign")
                    BATCH="11${LF}A${LF}Q"
                ;;
                auth)
                    BATCH="11${LF}S${LF}A${LF}Q"
                ;;
                sign)
                    BATCH=10
                ;;
            esac
            BATCH="$BATCH${LF}$SUBKEY_CURVE"
        ;;
    esac
    BATCH="addkey$LF$BATCH$LF${SUBKEY_LENGTH:-${SUBKEY_CURVE:-}}$LF$EXPIRE_DATE${LF}y${LF}save"
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
    SUBKEY_TYPE=
    SUBKEY_LENGTH=
    SUBKEY_CURVE=
    SUBKEY_USAGE=
    SUBKEY_IS_ADDITIONAL=
    EXPIRE_DATE=
    PASSPHRASE=
}

enable_next_subkey ()
{
    KEY_TEST=
    SUBKEY_TYPE=
    SUBKEY_IS_ADDITIONAL=
    while read -r SUBKEYWORD || test "${SUBKEYWORD:-}"
    do
        test "${SUBKEY_IS_ADDITIONAL:-}" ||
        case "${SUBKEYWORD:-}" in
            Subkey-Type:* | Subkey-Curve:* | Subkey-Length:* | Subkey-Usage:*)
                SUBKEYWORD="#$SUBKEYWORD"
            ;;
            \##Subkey-Type:*)
                test "${SUBKEY_TYPE:-}" && SUBKEY_IS_ADDITIONAL=yes || {
                    SUBKEYWORD="${SUBKEYWORD#??}"
                    SUBKEY_TYPE=1
                }
            ;;
            \##Subkey-Curve:* | \##Subkey-Length:* | \##Subkey-Usage:*)
                SUBKEYWORD="${SUBKEYWORD#??}"
            ;;
        esac
        KEY_TEST="${KEY_TEST:+"$KEY_TEST$LF"}$SUBKEYWORD"
    done <<BATCH
$KEY
BATCH
    KEY="$KEY_TEST"
}

check_key ()
{
    SAVE_KEY="$KEY"
    while :
    do
        DRY_RUN=yes
        gpg_generate_key --dry-run || return
        case "$KEY" in
            *$LF##*)
                enable_next_subkey
            ;;
            *)
                DRY_RUN=
                KEY="$SAVE_KEY"
                return
        esac
    done
}

run_batch ()
{
    case "${KEY:-}" in
        ?*)
            check_key &&
            gpg_generate_key
        ;;
    esac &&
    case "${SUBKEY:-}" in
        ?*)
            gpg_generate_subkey
        ;;
    esac || RETURN=$?
    set_batch_vars
}

run_batch_file ()
{
    set_batch_vars
    while read -r KEYWORD || test "${KEYWORD:-}"
    do
        case "${KEYWORD:-}" in
            \#*)
                KEYWORD=
            ;;
            %commit)
                run_batch
                continue
            ;;
            Key-Type:*)
                test -z "${KEY_TYPE:-}" || run_batch
            ;;
            Expire-Date:*)
                EXPIRE_DATE="${KEYWORD##*[[:blank:]]}"
            ;;
            Passphrase:*)
                PASSPHRASE="${KEYWORD#Passphrase:}"
                PASSPHRASE="${PASSPHRASE#"${PASSPHRASE%%[![:blank:]]*}"}"
            ;;
            Subkey-Type:*)
                test "${SUBKEY_TYPE:-}" && {
                    SUBKEY="${SUBKEY:+"$SUBKEY$LF"}$KEYWORD"
                    KEYWORD="##$KEYWORD"
                    SUBKEY_IS_ADDITIONAL=yes
                } || SUBKEY_TYPE=1
            ;;
            Subkey-Curve:* | Subkey-Length:* | Subkey-Usage:*)
                test "${SUBKEY_IS_ADDITIONAL:-}" && {
                    SUBKEY="${SUBKEY:+"$SUBKEY$LF"}$KEYWORD"
                    KEYWORD="##$KEYWORD"
                }
            ;;
        esac
        KEY="${KEY:+"$KEY$LF"}${KEYWORD:-}"
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
    return "${RETURN:-0}"
}

main "$@"
