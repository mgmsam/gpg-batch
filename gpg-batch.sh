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

is_diff ()
{
    case "${1:-}" in
        "${2:-}")
            return 1
        ;;
    esac
}

is_equal ()
{
    case "${1:-}" in
        "${2:-}")
            return 0
        ;;
    esac
    return 1
}

is_empty ()
{
    case "${1:-}" in
        ?*)
            return 1
        ;;
    esac
}

is_not_empty ()
{
    case "${1:-}" in
        "")
            return 1
        ;;
    esac
}

is_term ()
{
    test -t "${1:-1}" && IS_TERM=0 || IS_TERM=1
    return "$IS_TERM"
}

if is_not_empty "${KSH_VERSION:-}"
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
    while is_diff $# 0
    do
        case "${1:-}" in
            -n)
                is_equal "$PUTS" printf &&
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
    is_empty "$@" || {
        puts "$PKG:${1:+" $@"}"
        PUTS_OPTIONS=
    }
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
                is_not_empty "${ELEMENT:-}" || ELEMENT=.
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

mktempdir ()
{
    TMPDIR="${TMPDIR:-/tmp}"
    TRYCOUNT=3
    umask 077
    while :
    do
        TMPTRG="$TMPDIR/tmp.$(2>/dev/null date +%s)"
        test -e "$TMPTRG" || {
            >/dev/null 2>&1 mkdir -p -- "$TMPTRG" && {
                echo "$TMPTRG"
                return
            }
        } || :
        TRYCOUNT="$((TRYCOUNT - 1))"
        is_diff "$TRYCOUNT" 0 || {
            echo "mktempdir: failed to create directory: -- '$TMPTRG'"
            return 1
        }
    done
}

run_gpg ()
{
    "$GPG" --expert --batch "$@" <<BATCH
$BATCH
BATCH
}

gpg_update_trustdb ()
{
    >/dev/null 2>&1 run_gpg --update-trustdb || :
}

gpg_generate_key ()
{
    STATUS="$(run_gpg "$@" --full-gen-key --status-fd=1)" && {
        is_not_empty "${DRY_RUN:-}" || {
            gpg_update_trustdb
            KEY_ID="${STATUS##*KEY_CREATED}"
            KEY_ID="${KEY_ID##*[[:blank:]]}"
            KEY_CREATED="${KEY_CREATED:+"$KEY_CREATED "}$KEY_ID"
        }
    }
}

gpg_addkey ()
{
    if is_empty "${NO_PROTECTION:-"${PASSPHRASE:-}"}"
    then
        run_gpg --command-fd=0 --edit-key "$KEY_ID"
    else
        run_gpg --command-fd=0 --pinentry-mode=loopback --edit-key "$KEY_ID"
    fi
}

parse_usage ()
{
    IFS="$IFS,"
    set -- $SUBKEY_USAGE
    while is_diff $# 0
    do
        case "$1" in
            auth)
                AUTH=auth
                ;;
            cert)
                CERT=cert
                ;;
            encrypt)
                ENCRYPT=encrypt
                ;;
            sign)
                SIGN=sign
        esac
        shift
    done
    set -- ${AUTH:-} ${CERT:-} ${ENCRYPT:-} ${SIGN:-}
    echo "$@"
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
    while read -r SUBKEYWORD || is_not_empty "${SUBKEYWORD:-}"
    do
        case "$SUBKEYWORD" in
            Expire-Date:*)
                EXPIRE_DATE="${SUBKEYWORD#Expire-Date:}"
                EXPIRE_DATE="${EXPIRE_DATE#"${EXPIRE_DATE%%[![:blank:]]*}"}"
            ;;
            Subkey-Type:*)
                is_empty "${SUBKEY_TYPE:-}" || break
                SUBKEY_TYPE="${SUBKEYWORD#Subkey-Type:}"
                SUBKEY_TYPE="${SUBKEY_TYPE#"${SUBKEY_TYPE%%[![:blank:]]*}"}"
            ;;
            Subkey-Length:*)
                SUBKEY_LENGTH="${SUBKEYWORD#Subkey-Length:}"
                SUBKEY_LENGTH="${SUBKEY_LENGTH#"${SUBKEY_LENGTH%%[![:blank:]]*}"}"
            ;;
            Subkey-Curve:*)
                SUBKEY_CURVE="${SUBKEYWORD#Subkey-Curve:}"
                SUBKEY_CURVE="${SUBKEY_CURVE#"${SUBKEY_CURVE%%[![:blank:]]*}"}"
                SUBKEY_CURVE="$(parse_curve)"
            ;;
            Subkey-Usage:*)
                SUBKEY_USAGE="${SUBKEYWORD#Subkey-Usage:}"
                SUBKEY_USAGE="$(parse_usage)"
            ;;
        esac
        SUBKEY="${SUBKEY#"$SUBKEYWORD"}"
        SUBKEY="${SUBKEY#"$LF"}"
    done <<SUBKEY
$SUBKEY
SUBKEY
}

build_batch ()
{
    case "${SUBKEY_TYPE:-}" in
        1 | [rR][sS][aA])
            case "${SUBKEY_USAGE:-}" in
                "" | "auth encrypt sign" | "auth cert encrypt sign")
                    BATCH="8${LF}A${LF}Q"
                ;;
                "auth sign" | "auth cert sign")
                    BATCH="8${LF}E${LF}A${LF}Q"
                ;;
                "auth encrypt" | "auth cert encrypt")
                    BATCH="8${LF}S${LF}A${LF}Q"
                ;;
                "encrypt sign" | "cert encrypt sign")
                    BATCH="8${LF}Q"
                ;;
                auth | "auth cert")
                    BATCH="8${LF}S${LF}E${LF}A${LF}Q"
                ;;
                cert)
                    BATCH="8${LF}S${LF}E${LF}Q"
                ;;
                encrypt | "cert encrypt")
                    BATCH=6
                ;;
                sign | "cert sign")
                    BATCH=4
                ;;
            esac
            BATCH="$BATCH$LF${SUBKEY_LENGTH:-}"
        ;;
        16 | ELG | ELG-E)
            BATCH="5$LF${SUBKEY_LENGTH:-}"
        ;;
        17 | [dD][sS][aA])
            case "${SUBKEY_USAGE:-}" in
                "" | "auth cert sign" | "auth cert" | "auth sign")
                    BATCH="7${LF}A${LF}Q"
                ;;
                auth)
                    BATCH="7${LF}S${LF}A${LF}Q"
                ;;
                cert)
                    BATCH="7${LF}S${LF}Q"
                ;;
                sign)
                    BATCH=3
                ;;
            esac
            BATCH="$BATCH$LF${SUBKEY_LENGTH:-}"
        ;;
        18 | [eE][cC][cC] | [eE][cC][dD][hH])
            case "$SUBKEY_CURVE" in
                0)
                    SUBKEY_CURVE=1
                ;;
            esac
            BATCH="12$LF$SUBKEY_CURVE"
        ;;
        19 | 22 | [eE][cCdD][dD][sS][aA] | [dD][eE][fF][aA][uU][lL][tT])
            case "${SUBKEY_USAGE:-}" in
                "" | "auth sign" | "auth cert sign")
                    BATCH="11${LF}A${LF}Q"
                ;;
                auth | "auth cert")
                    BATCH="11${LF}S${LF}A${LF}Q"
                ;;
                cert)
                    BATCH="11${LF}S${LF}Q"
                ;;
                sign | "cert sign")
                    BATCH=10
                ;;
            esac
            BATCH="$BATCH$LF$SUBKEY_CURVE"
        ;;
    esac

    is_not_empty "${PASSPHRASE:-}" &&
    BATCH="addkey$LF$BATCH$LF${EXPIRE_DATE:-}$LF$PASSPHRASE${LF}save" ||
    BATCH="addkey$LF$BATCH$LF${EXPIRE_DATE:-}$LF${NO_PROTECTION:+y$LF}save"
}

gpg_generate_subkey ()
{
    while is_not_empty "${SUBKEY:-}"
    do
        get_subkey
        build_batch
        gpg_addkey || GPG_EXIT=$?
    done
}

include_subkey ()
{
    UPDATED_KEY=

    is_not_empty "${EXPIRE_DATE_IS_ADDITIONAL:+"${SUBKEY_TYPE:-}"}" && {
        while read -r LINE || is_not_empty "${LINE:-}"
        do
            case "${LINE:-}" in
                \#[!#]*)
                    UPDATED_KEY="${UPDATED_KEY:+"$UPDATED_KEY$LF"}#$LINE"
                ;;
                *)
                    UPDATED_KEY="${UPDATED_KEY:+"$UPDATED_KEY$LF"}${LINE:-}"
                ;;
            esac
        done <<KEY
$KEY
KEY
    } || {
        SUBKEY_FIRST=
        while read -r LINE || is_not_empty "${LINE:-}"
        do
            case "${LINE:-}" in
                \#[!#]*)
                    UPDATED_KEY="${UPDATED_KEY:+"$UPDATED_KEY$LF"}${LINE#?}"
                ;;
                *)
                    UPDATED_KEY="${UPDATED_KEY:+"$UPDATED_KEY$LF"}${LINE:-}"
                ;;
            esac
        done <<KEY
$KEY
KEY
    }

    KEY="$UPDATED_KEY"
    SUBKEY="${SUBKEY_FIRST:-}${SUBKEY:+"$LF$SUBKEY"}"
}

enable_next_subkey ()
{
    UPDATED_KEY=
    SUBKEY_TYPE=
    SUBKEY_IS_ADDITIONAL=
    while read -r SUBKEYWORD || is_not_empty "${SUBKEYWORD:-}"
    do
        is_not_empty "${SUBKEY_IS_ADDITIONAL:-}" ||
        case "${SUBKEYWORD:-}" in
            Expire-Date:* | Subkey-Type:* | Subkey-Curve:* | Subkey-Length:* | Subkey-Usage:*)
                SUBKEYWORD="#$SUBKEYWORD"
            ;;
            \##Subkey-Type:*)
                is_not_empty "${SUBKEY_TYPE:-}" && SUBKEY_IS_ADDITIONAL=yes || {
                    SUBKEYWORD="${SUBKEYWORD#??}"
                    SUBKEY_TYPE=1
                }
            ;;
            \##Expire-Date:* | \##Subkey-Curve:* | \##Subkey-Length:* | \##Subkey-Usage:*)
                SUBKEYWORD="${SUBKEYWORD#??}"
            ;;
        esac
        UPDATED_KEY="${UPDATED_KEY:+"$UPDATED_KEY$LF"}$SUBKEYWORD"
    done <<KEY
$TESTED_KEY
KEY
    TESTED_KEY="$UPDATED_KEY"
}

extend_canvas ()
{
    while read -r LINE || is_not_empty "${LINE:-}"
    do
        CANVAS="${CANVAS:-}$LF"
    done <<KEY
$KEY
KEY
}

check_key ()
{
    ORIGINAL_GNUPGHOME="${GNUPGHOME:-}"
    export   GNUPGHOME="$TMP_GNUPGHOME"
    say -n "checking the GPG key parameters:"
    TESTED_KEY="$KEY$LF%no-protection"
    while :
    do
        DRY_RUN=yes
        BATCH="${CANVAS:-}$TESTED_KEY"
        STATUS="$(2>&1 gpg_generate_key --dry-run)" || {
            GPG_EXIT=$?
            GNUPGHOME="${ORIGINAL_GNUPGHOME:-}"
            extend_canvas
            echo " failed$LF$STATUS"
            return "$GPG_EXIT"
        }
        case "$TESTED_KEY" in
            *$LF##*)
                enable_next_subkey
            ;;
            *)
                DRY_RUN=
                BATCH="${CANVAS:-}$KEY"
                GNUPGHOME="${ORIGINAL_GNUPGHOME:-}"
                extend_canvas
                echo " passed"
                return
            ;;
        esac
    done
}

add_passphrase ()
{
    case "${STDIN_PASSPHRASE:-}" in
        "")
            is_empty "${NO_PROTECTION:-}" || {
                BATCH="$BATCH$LF%no-protection"
                PASSPHRASE=
            }
        ;;
        "$LF")
            is_empty "${KEY_TYPE:-}" || {
                BATCH="$BATCH$LF%no-protection"
                PASSPHRASE=
                NO_PROTECTION=yes
            }
        ;;
        *)
            is_not_empty "${PASSPHRASE:-}" || {
                is_empty "${KEY_TYPE:-}" || {
                    PASSPHRASE="$STDIN_PASSPHRASE"
                    BATCH="$BATCH${LF}Passphrase: ${PASSPHRASE:-}"
                }
            }
            NO_PROTECTION=
        ;;
    esac
}

run_batch ()
{
    case "${KEY:-}" in
        *[![:space:]]*)
            include_subkey
            check_key &&
            add_passphrase &&
            gpg_generate_key
        ;;
    esac &&
    case "${SUBKEY:-}" in
        ?*)
            gpg_generate_subkey
        ;;
    esac || {
        GPG_EXIT=$?
        say "$GPG_EXIT" "error in the file: -- '$BATCH_FILE'"
    }
    set_batch_vars
}

set_batch_vars ()
{
    KEY=
    KEY_TYPE=
    SUBKEY=
    SUBKEY_TYPE=
    SUBKEY_LENGTH=
    SUBKEY_CURVE=
    SUBKEY_USAGE=
    SUBKEY_FIRST=
    SUBKEY_IS_ADDITIONAL=
    EXPIRE_DATE=
    EXPIRE_DATE_IS_ADDITIONAL=
    NO_PROTECTION=
    PASSPHRASE=
}

run_batch_file ()
{
    CANVAS=
    set_batch_vars
    while read -r KEYWORD || is_not_empty "${KEYWORD:-}"
    do
        case "${KEYWORD:-}" in
            \#*)
                KEYWORD=
            ;;
            %commit)
                run_batch
                KEYWORD=
            ;;
            %no-protection)
                NO_PROTECTION=yes
                KEYWORD=
            ;;
            Key-Type:*)
                is_empty "${KEY_TYPE:-}" && KEY_TYPE=1 || run_batch
            ;;
            Expire-Date:*)
                is_empty "${EXPIRE_DATE:-}" &&
                EXPIRE_DATE="${KEYWORD##*[[:blank:]]}" || {
                    EXPIRE_DATE_IS_ADDITIONAL=yes
                    is_empty "${SUBKEY_IS_ADDITIONAL:-}" && {
                        SUBKEY_FIRST="${SUBKEY_FIRST:+"$SUBKEY_FIRST$LF"}$KEYWORD"
                        KEYWORD="#$KEYWORD"
                    } || {
                        SUBKEY="${SUBKEY:+"$SUBKEY$LF"}$KEYWORD"
                        KEYWORD="##$KEYWORD"
                    }
                }
            ;;
            Passphrase:*)
                PASSPHRASE="${KEYWORD#Passphrase:}"
                PASSPHRASE="${PASSPHRASE#"${PASSPHRASE%%[![:blank:]]*}"}"
                is_empty "${PASSPHRASE:-}" || {
                    case "${STDIN_PASSPHRASE:-}" in
                        "")
                            KEYWORD="Passphrase: $PASSPHRASE"
                        ;;
                        "$LF")
                            KEYWORD=
                            PASSPHRASE=
                        ;;
                        *)
                            KEYWORD="Passphrase: $STDIN_PASSPHRASE"
                            PASSPHRASE="$STDIN_PASSPHRASE"
                        ;;
                    esac
                }
            ;;
            Subkey-Type:*)
                is_empty "${SUBKEY_TYPE:-}" && {
                    SUBKEY_FIRST="${SUBKEY_FIRST:+"$SUBKEY_FIRST$LF"}$KEYWORD"
                    SUBKEY_TYPE=1
                    KEYWORD="#$KEYWORD"
                } || {
                    SUBKEY="${SUBKEY:+"$SUBKEY$LF"}$KEYWORD"
                    SUBKEY_IS_ADDITIONAL=yes
                    KEYWORD="##$KEYWORD"
                }
            ;;
            Subkey-Curve:* | Subkey-Length:* | Subkey-Usage:*)
                is_empty "${SUBKEY_IS_ADDITIONAL:-}" && {
                    SUBKEY_FIRST="${SUBKEY_FIRST:+"$SUBKEY_FIRST$LF"}$KEYWORD"
                    KEYWORD="#$KEYWORD"
                } || {
                    SUBKEY="${SUBKEY:+"$SUBKEY$LF"}$KEYWORD"
                    KEYWORD="##$KEYWORD"
                }
            ;;
        esac
        KEY="${KEY:+"$KEY$LF"}${KEYWORD:-}"
    done < "$1"
    is_empty "${KEY:-"${SUBKEY:-}"}" && return || run_batch
}

main ()
{
    PKG="${0##*/}"
    GPG="$(which gpg)" || die "gpg: command not found"
    TMP_GNUPGHOME="${TMP_GNUPGHOME:-"$(mktempdir)"}" || die "$TMP_GNUPGHOME"

    for BATCH_FILE in "$@"
    do
        run_batch_file "$BATCH_FILE"
    done
    gpg_update_trustdb
    is_empty "${KEY_CREATED:-}" || say 0 "key created: $KEY_CREATED"
    STATUS="$(2>&1 rm -rvf -- "$TMP_GNUPGHOME")" || die "[TMP_GNUPGHOME] $STATUS"
    return "${GPG_EXIT:-0}"
}

LF='
'
is_term 0 ||
while IFS="$LF" read -r STDIN_PASSPHRASE || is_not_empty "${STDIN_PASSPHRASE:-}"
do
    STDIN_PASSPHRASE="${STDIN_PASSPHRASE:-"$LF"}"
    break
done

main "$@"
