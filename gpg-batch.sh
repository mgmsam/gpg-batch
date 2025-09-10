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

is_dir ()
{
    test -d "${1:-}"
}

is_exists ()
{
    test -e "${1:-}"
}

is_file ()
{
    test -f "${1:-}"
}

is_file_readable ()
{
    is_file "${1:-}" || {
        is_exists "${1:-}" &&
        say 2 "is not a file: -- '${1:-}'" ||
        say 2 "no such file: -- '${1:-}'"
        return 2
    } >&2
    test -r "${1:-}" || {
        say 1 "no read permissions: -- '${1:-}'" >&2
        return 1
    }
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
        TMPTRG="$TMPDIR/${PKG:-tmp}.$(2>/dev/null "$DATE" +%s)"
        test -e "$TMPTRG" || {
            >/dev/null 2>&1 "$MKDIR" -p -- "$TMPTRG" && {
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
    "$GPG" ${GPG_OPTIONS:+--options "$GPG_OPTIONS"} ${NO_TTY:-} ${VERBOSE:-} ${QUIET:-} "$@"
}

gpg_update_trustdb ()
{
    >/dev/null 2>&1 run_gpg --update-trustdb || :
}

gpg_run_batch ()
{
    run_gpg --expert --batch "$@" <<BATCH
$BATCH
BATCH
}

gpg_generate_key ()
{
    gpg_run_batch --full-gen-key --status-fd=1 "$@"
}

set_subkey_curve ()
{
    case "${SUBKEY_CURVE:-}" in
        cv25519)
            SUBKEY_CURVE=0
        ;;
        ed25519)
            SUBKEY_CURVE=1
        ;;
        ed448)
            SUBKEY_CURVE=2
        ;;
        nistp256)
            SUBKEY_CURVE=3
        ;;
        nistp384)
            SUBKEY_CURVE=4
        ;;
        nistp521)
            SUBKEY_CURVE=5
        ;;
        brainpoolP256r1)
            SUBKEY_CURVE=6
        ;;
        brainpoolP384r1)
            SUBKEY_CURVE=7
        ;;
        brainpoolP512r1)
            SUBKEY_CURVE=8
        ;;
        secp256k1)
            SUBKEY_CURVE=9
        ;;
    esac
}

set_subkey_usage ()
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
    SUBKEY_USAGE="$*"
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
                set_subkey_curve
            ;;
            Subkey-Usage:*)
                SUBKEY_USAGE="${SUBKEYWORD#Subkey-Usage:}"
                set_subkey_usage
            ;;
        esac
        SUBKEY="${SUBKEY#"$SUBKEYWORD"}"
        SUBKEY="${SUBKEY#"$LF"}"
    done <<SUBKEY
$SUBKEY
SUBKEY
}

get_key_type ()
{
    case "${1:-}" in
        1 | [rR][sS][aA])
            echo RSA
        ;;
        16 | ELG)
            echo ELG
        ;;
        ELG-E)
            echo ELG-E
        ;;
        17 | [dD][sS][aA])
            echo DSA
        ;;
        18 | [eE][cC][cC])
            echo ECC
        ;;
        [eE][cC][dD][hH])
            echo ECDH
        ;;
        19 | [eE][cC][dD][sS][aA])
            echo ECDSA
        ;;
        22 | [eE][dD][dD][sS][aA] | [dD][eE][fF][aA][uU][lL][tT])
            echo EDDSA
        ;;
    esac
}

build_batch ()
{
    case "${SUBKEY_TYPE:-}" in
        RSA)
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
        ELG | ELG-E)
            BATCH="5$LF${SUBKEY_LENGTH:-}"
        ;;
        DSA)
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
        ECC | ECDH)
            case "$SUBKEY_CURVE" in
                0)
                    SUBKEY_CURVE=1
                ;;
            esac
            BATCH="12$LF$SUBKEY_CURVE"
        ;;
        ECDSA | EDDSA)
            case "${SUBKEY_USAGE:-}" in
                "" | cert)
                    BATCH="11${LF}S${LF}Q"
                ;;
                "auth sign" | "auth cert sign")
                    BATCH="11${LF}A${LF}Q"
                ;;
                auth | "auth cert")
                    BATCH="11${LF}S${LF}A${LF}Q"
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

gpg_edit_key ()
{
    if is_empty "${NO_PROTECTION:-"${PASSPHRASE:-}"}"
    then
        gpg_run_batch --command-fd=0 --edit-key "$KEY_ID"
    else
        gpg_run_batch --command-fd=0 --pinentry-mode=loopback --edit-key "$KEY_ID"
    fi || {
        GPG_EXIT=$?
        return "$GPG_EXIT"
    }
}

gpg_generate_subkey ()
{
    while is_not_empty "${SUBKEY:-}"
    do
        get_subkey
        SUBKEY_TYPE="$(get_key_type "$SUBKEY_TYPE")"
        build_batch
        is_empty "${VERBOSE:-}" && {
            gpg_edit_key || break
        } || {
            say "generating the GPG subkey [$SUBKEY_TYPE]: ..."
            gpg_edit_key &&
                say "generating the GPG subkey [$SUBKEY_TYPE]: success" || {
                    say "generating the GPG subkey [$SUBKEY_TYPE]: failed"
                    break
                }
        }
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
        is_not_empty "${GPG_EDIT_KEY_ID:-}" || SUBKEY_FIRST=
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

check_batch ()
{
    while :
    do
        BATCH="${CANVAS:-}$TESTED_KEY"
        gpg_generate_key --homedir "$TMP_GNUPGHOME" --dry-run || return
        case "$TESTED_KEY" in
            *$LF##*)
                enable_next_subkey
            ;;
            *)
                return
            ;;
        esac
    done 2>&1 >/dev/null
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

set_protection ()
{
    case "${STDIN_PASSPHRASE:-}" in
        "")
            is_empty "${NO_PROTECTION:-}" || {
                PASSPHRASE=
                BATCH="$BATCH$LF%no-protection"
            }
        ;;
        "$LF")
            is_empty "${KEY_TYPE:-"${SUBKEY_TYPE:-}"}" || {
                PASSPHRASE=
                BATCH="$BATCH$LF%no-protection"
                NO_PROTECTION=yes
            }
        ;;
        *)
            is_not_empty "${PASSPHRASE:-}" || {
                is_empty "${KEY_TYPE:-"${SUBKEY_TYPE:-}"}" || {
                    PASSPHRASE="$STDIN_PASSPHRASE"
                    BATCH="$BATCH${LF}Passphrase: ${PASSPHRASE:-}"
                }
            }
            NO_PROTECTION=
        ;;
    esac
}

get_error_line_number ()
{
    GPG_EXIT=$?
    ERROR_LINE="$(echo "$STATUS" | "$GREP" -o "^\(gpg: -:\)[0-9]\+")"
    ERROR_LINE="${ERROR_LINE##*:}"
    is_empty "${ERROR_LINE:-}" ||
    STATUS="$(echo "$STATUS" | "$SED" "s%^\(gpg: \)-:[0-9]\+%\1$BATCH_FILE:$((ERROR_LINE - 1))%")"
    return "$GPG_EXIT"
}

add_batch_filename ()
{
    GPG_EXIT=$?
    ERROR_LINE="$(echo "$STATUS" | "$GREP" -o "^\(gpg: -:\)")"
    is_empty "${ERROR_LINE:-}" ||
    STATUS="$(echo "$STATUS" | "$SED" "s%^\(gpg: \)-:%\1$BATCH_FILE:%")"
    return "$GPG_EXIT"
}

run_batch ()
{
    include_subkey
    is_empty "${VERBOSE:-}" || say -n "checking the GPG key parameters:"
    TESTED_KEY="$KEY$LF%no-protection"
    if is_not_empty "${GPG_EDIT_KEY_ID:-}"
    then
        is_not_empty "${NAME_REAL:-}" || TESTED_KEY="$TESTED_KEY${LF}Name-Real: $PKG"
        if is_empty "${KEY_TYPE:-}"
        then
            TESTED_KEY="Key-Type: 1$LF$TESTED_KEY"
            STATUS="$(check_batch)" || get_error_line_number
        else
            STATUS="$(check_batch)" || add_batch_filename
        fi && {
            KEY_ID="${GPG_EDIT_KEY_ID:-}"
            extend_canvas
            is_empty "${VERBOSE:-}" || echo " passed"
            set_protection
        }
    else
        STATUS="$(check_batch)" || add_batch_filename && {
            BATCH="${CANVAS:-}$KEY"
            is_empty "${VERBOSE:-}" || echo " passed"
            set_protection
            gpg_update_trustdb
            KEY_TYPE="${KEY_TYPE#*:}"
            KEY_TYPE="${KEY_TYPE#"${KEY_TYPE%%[![:blank:]]*}"}"
            KEY_TYPE="$(get_key_type "$KEY_TYPE")"
            is_empty "${VERBOSE:-}" || say "generating the GPG key [$KEY_TYPE]: ..."
            STATUS="$(gpg_generate_key)" && {
                extend_canvas
                KEY_ID="${STATUS##*KEY_CREATED}"
                KEY_ID="${KEY_ID##*[[:blank:]]}"
                KEY_CREATED="${KEY_CREATED:+"$KEY_CREATED "}$KEY_ID"
                is_empty "${VERBOSE:-}" || say "generating the GPG key [$KEY_TYPE]: success"
            }
        }
    fi &&
    case "${SUBKEY:-}" in
        ?*)
            gpg_update_trustdb
            gpg_generate_subkey
        ;;
    esac || {
        GPG_EXIT=$?
        extend_canvas
        is_empty "${VERBOSE:-}" &&  echo "${STATUS:-}" ||
                                    echo " failed${STATUS:+"$LF$STATUS"}"
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
    NAME_REAL=
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
                is_empty "${KEY_TYPE:-}" && KEY_TYPE="$KEYWORD" || run_batch
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
            Name-Real:*)
                NAME_REAL=1
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
    done < "$BATCH_FILE"
    is_empty "${KEY:-"${SUBKEY:-}"}" && return || run_batch
}

check_dependencies ()
{
     DATE="$(which date)"  || die  "date: command not found"
     GREP="$(which grep)"  || die  "grep: command not found"
      GPG="$(which gpg)"   || die   "gpg: command not found"
    MKDIR="$(which mkdir)" || die "mkdir: command not found"
       RM="$(which rm)"    || die    "rm: command not found"
      SED="$(which sed)"   || die   "sed: command not found"
}

main ()
{
    check_dependencies
    TMP_GNUPGHOME="${TMP_GNUPGHOME:-"$(mktempdir)"}" || die "$TMP_GNUPGHOME"
    is_empty "${GPG_OPTIONS:-}" || is_file_readable "$GPG_OPTIONS" || die
    is_empty  "${GNUPGHOME:-}"  || {
        is_dir "$GNUPGHOME" || die 2 "no such directory: -- '$GNUPGHOME'"
        export   GNUPGHOME
    }
    is_empty "${GPG_EDIT_KEY_ID:-}" ||
        >/dev/null 2>&1 run_gpg --list-keys "$GPG_EDIT_KEY_ID" ||
            die "key not found: -- '$GPG_EDIT_KEY_ID'"

    is_diff $# 0 || die 2 "no batch file specified"

    for BATCH_FILE in "$@"
    do
        is_file_readable "${BATCH_FILE:-}" || {
            GPG_EXIT=2
            break
        }
        run_batch_file
    done
    gpg_update_trustdb
    is_empty "${KEY_CREATED:+"${VERBOSE:-}"}" || say 0 "key created: $KEY_CREATED"
    STATUS="$(2>&1 "$RM" -rvf -- "$TMP_GNUPGHOME")" || die "[TMP_GNUPGHOME] $STATUS"
    return "${GPG_EXIT:-0}"
}

PKG="${0##*/}"
LF='
'
is_term 0 ||
while IFS="$LF" read -r STDIN_PASSPHRASE || is_not_empty "${STDIN_PASSPHRASE:-}"
do
    STDIN_PASSPHRASE="${STDIN_PASSPHRASE:-"$LF"}"
    break
done

arg_is_not_empty ()
{
    is_not_empty "${2:-}"  ||
        die 2 "$PREFIX: missing argument for option \"$1\""
}

invalid_option ()
{
    is_equal "${#1}" 2 &&
    die 2 "$PREFIX: invalid option -- '${1#?}'" ||
    die 2 "$PREFIX: unrecognized option '$1'"
}

ARG_NUM=0
while is_diff $# 0
do
    ARG_NUM=$((ARG_NUM + 1))
    PREFIX="${ARG_NUM}th argument"
    case "${1:-}" in
        --edit-key)
            arg_is_not_empty "$1" "${2:-}"
            ARG_NUM="$((ARG_NUM + 1))" GPG_EDIT_KEY_ID="$2"
            shift
        ;;
        --edit-key=*)
            arg_is_not_empty "${1%%=*}" "${1#*=}"
            GPG_EDIT_KEY_ID="${1#*=}"
        ;;
        --homedir)
            arg_is_not_empty "$1" "${2:-}"
            ARG_NUM="$((ARG_NUM + 1))" GNUPGHOME="$2"
            shift
        ;;
        --homedir=*)
            arg_is_not_empty "${1%%=*}" "${1#*=}"
            GNUPGHOME="${1#*=}"
        ;;
        --no-tty)
            NO_TTY=--no-tty
        ;;
        --options)
            arg_is_not_empty "$1" "${2:-}"
            ARG_NUM="$((ARG_NUM + 1))" GPG_OPTIONS="$2"
            shift
        ;;
        --options=*)
            arg_is_not_empty "${1%%=*}" "${1#*=}"
            GPG_OPTIONS="${1#*=}"
        ;;
        -q | --quiet)
            QUIET=--quiet
        ;;
        -q*)
            QUIET=--quiet
            ARG="-${1#??}"
            shift
            set -- '' "$ARG" "$@"
        ;;
        -v | --verbose)
            VERBOSE="${VERBOSE:+"$VERBOSE "}--verbose"
        ;;
        -v*)
            VERBOSE="${VERBOSE:+"$VERBOSE "}--verbose"
            ARG="-${1#??}"
            shift
            set -- '' "$ARG" "$@"
        ;;
        --)
            shift
            break
        ;;
        -*)
            invalid_option "$1"
        ;;
        *)
            break
    esac
    shift
done
unset -v ARG_NUM PREFIX

main "$@"
