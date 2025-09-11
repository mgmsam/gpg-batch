#!/bin/sh
# gpg-batch.sh. Unattended key generation.
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

usage ()
{
    echo "
Usage: $PKG [OPTION] [--] BATCHFILE ...
   or: $PKG [OPTION] --edit-key <key-ID> [--] BATCHFILE ..."
}

show_help ()
{
    is_empty "${GPG:-}" && >&2 say "gpg: command not found" || "$GPG" --version
    usage
    echo "
Commands:
      --edit-key <key-ID>   edit a key

Options:
      --homedir dir         Set the name of the home directory to dir. If this
                            option is not used, the home directory defaults to
                            ‘~/.gnupg’. It is only recognized when given on the
                            command line. It also overrides any home directory
                            stated through the environment variable ‘GNUPGHOME’
                            or (on Windows systems) by means of the Registry
                            entry HKCU\Software\GNU\GnuPG:HomeDir.

      --version             display version information and exit
  -h, -?, --help            display this help and exit

Options controlling the diagnostic output:
  -v, --verbose             verbose
  -q, --quiet               be somewhat more quiet
      --options FILE        read options from FILE
      --no-tty              Make sure that the TTY (terminal) is never used for
                            any output. This option is needed in some cases
                            because GnuPG sometimes prints warnings to the TTY
                            even if --batch is used.

An argument of '--' disables further option processing

Report bugs to: bug-$PKG@mgmsam.pro
$PKG home page: <https://www.mgmsam.pro/shell-script/$PKG/>"
    exit
}

show_version ()
{
    echo "${0##*/} 0.0.1 - (C) 11.09.2025

Written by Mironov A Semyon
Site       www.mgmsam.pro
Email      s.mironov@mgmsam.pro"
    exit
}

try ()
{
    say "$@" >&2
    echo "Try '$PKG --help' for more information." >&2
    exit "$RETURN"
}

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

can_read_file ()
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
    "$GPG" ${OPTIONS_FILE:+--options "$OPTIONS_FILE"} ${NO_TTY:-} ${VERBOSE:-} ${QUIET:-} "$@"
}

gpg_update_trustdb ()
{
    >/dev/null 2>&1 run_gpg --update-trustdb || :
}

run_gpg_batch ()
{
    run_gpg --expert --batch "$@" <<EOF
$KEY_SETTINGS
EOF
}

gpg_generate_key ()
{
    run_gpg_batch --full-generate-key --status-fd=1 "$@"
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
    AUTH=
    CERT=
    ENCRYPT=
    SIGN=
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

get_subkey_settings ()
{
    SUBKEY_TYPE=
    SUBKEY_LENGTH=
    SUBKEY_CURVE=
    SUBKEY_USAGE=
    while read -r LINE || is_not_empty "${LINE:-}"
    do
        case "${LINE:-}" in
            Expire-Date:*)
                EXPIRE_DATE="${LINE#Expire-Date:}"
                EXPIRE_DATE="${EXPIRE_DATE#"${EXPIRE_DATE%%[![:blank:]]*}"}"
            ;;
            Subkey-Type:*)
                is_empty "${SUBKEY_TYPE:-}" || break
                SUBKEY_TYPE="${LINE#Subkey-Type:}"
                SUBKEY_TYPE="${SUBKEY_TYPE#"${SUBKEY_TYPE%%[![:blank:]]*}"}"
            ;;
            Subkey-Length:*)
                SUBKEY_LENGTH="${LINE#Subkey-Length:}"
                SUBKEY_LENGTH="${SUBKEY_LENGTH#"${SUBKEY_LENGTH%%[![:blank:]]*}"}"
            ;;
            Subkey-Curve:*)
                SUBKEY_CURVE="${LINE#Subkey-Curve:}"
                SUBKEY_CURVE="${SUBKEY_CURVE#"${SUBKEY_CURVE%%[![:blank:]]*}"}"
                set_subkey_curve
            ;;
            Subkey-Usage:*)
                SUBKEY_USAGE="${LINE#Subkey-Usage:}"
                set_subkey_usage
            ;;
        esac
        SUBKEY="${SUBKEY#"$LINE"}"
        SUBKEY="${SUBKEY#"$LF"}"
    done <<EOF
$SUBKEY
EOF
    SUBKEY_TYPE="$(get_key_type "$SUBKEY_TYPE")"
}

build_subkey_generation_command ()
{
    case "${SUBKEY_TYPE:-}" in
        RSA)
            case "${SUBKEY_USAGE:-}" in
                "" | "auth encrypt sign" | "auth cert encrypt sign")
                    KEY_SETTINGS="8${LF}A${LF}Q"
                ;;
                "auth sign" | "auth cert sign")
                    KEY_SETTINGS="8${LF}E${LF}A${LF}Q"
                ;;
                "auth encrypt" | "auth cert encrypt")
                    KEY_SETTINGS="8${LF}S${LF}A${LF}Q"
                ;;
                "encrypt sign" | "cert encrypt sign")
                    KEY_SETTINGS="8${LF}Q"
                ;;
                auth | "auth cert")
                    KEY_SETTINGS="8${LF}S${LF}E${LF}A${LF}Q"
                ;;
                cert)
                    KEY_SETTINGS="8${LF}S${LF}E${LF}Q"
                ;;
                encrypt | "cert encrypt")
                    KEY_SETTINGS=6
                ;;
                sign | "cert sign")
                    KEY_SETTINGS=4
                ;;
            esac
            KEY_SETTINGS="$KEY_SETTINGS$LF${SUBKEY_LENGTH:-}"
        ;;
        ELG | ELG-E)
            KEY_SETTINGS="5$LF${SUBKEY_LENGTH:-}"
        ;;
        DSA)
            case "${SUBKEY_USAGE:-}" in
                "" | "auth cert sign" | "auth cert" | "auth sign")
                    KEY_SETTINGS="7${LF}A${LF}Q"
                ;;
                auth)
                    KEY_SETTINGS="7${LF}S${LF}A${LF}Q"
                ;;
                cert)
                    KEY_SETTINGS="7${LF}S${LF}Q"
                ;;
                sign)
                    KEY_SETTINGS=3
                ;;
            esac
            KEY_SETTINGS="$KEY_SETTINGS$LF${SUBKEY_LENGTH:-}"
        ;;
        ECC | ECDH)
            case "$SUBKEY_CURVE" in
                0)
                    SUBKEY_CURVE=1
                ;;
            esac
            KEY_SETTINGS="12$LF$SUBKEY_CURVE"
        ;;
        ECDSA | EDDSA)
            case "${SUBKEY_USAGE:-}" in
                "" | cert)
                    KEY_SETTINGS="11${LF}S${LF}Q"
                ;;
                "auth sign" | "auth cert sign")
                    KEY_SETTINGS="11${LF}A${LF}Q"
                ;;
                auth | "auth cert")
                    KEY_SETTINGS="11${LF}S${LF}A${LF}Q"
                ;;
                sign | "cert sign")
                    KEY_SETTINGS=10
                ;;
            esac
            KEY_SETTINGS="$KEY_SETTINGS$LF$SUBKEY_CURVE"
        ;;
    esac

    is_not_empty "${PASSPHRASE:-}" &&
    KEY_SETTINGS="addkey$LF$KEY_SETTINGS$LF${EXPIRE_DATE:-}$LF$PASSPHRASE${LF}save" ||
    KEY_SETTINGS="addkey$LF$KEY_SETTINGS$LF${EXPIRE_DATE:-}$LF${NO_PROTECTION:+y$LF}save"
}

gpg_edit_key ()
{
    if is_empty "${NO_PROTECTION:-"${PASSPHRASE:-}"}"
    then
        run_gpg_batch --command-fd=0 --edit-key "$KEY_ID"
    else
        run_gpg_batch --command-fd=0 --pinentry-mode=loopback --edit-key "$KEY_ID"
    fi || {
        GPG_RETURN_CODE=$?
        return "$GPG_RETURN_CODE"
    }
}

gpg_generate_subkey ()
{
    is_empty "${VERBOSE:-}" && {
        while is_not_empty "${SUBKEY:-}"
        do
            get_subkey_settings
            build_subkey_generation_command
            gpg_edit_key || return 0
        done
    } || {
        while is_not_empty "${SUBKEY:-}"
        do
            get_subkey_settings
            build_subkey_generation_command
            say "generating the GPG subkey [$SUBKEY_TYPE]: ..."
            gpg_edit_key &&
            say "generating the GPG subkey [$SUBKEY_TYPE]: success" || {
                say "generating the GPG subkey [$SUBKEY_TYPE]: failed"
                return
            }
        done
    }
}

include_subkey ()
{
    TMP=

    is_empty "${EXPIRE_DATE_IS_ADDITIONAL:+"${SUBKEY_TYPE:-}"}" && {
        is_not_empty "${GPG_EDIT_KEY_ID:-}" || FIRST_SUBKEY=
        while read -r LINE || is_not_empty "${LINE:-}"
        do
            case "${LINE:-}" in
                \#[!#]*)
                    TMP="${TMP:-}${LINE#?}$LF"
                ;;
                *)
                    TMP="${TMP:-}${LINE:-}$LF"
                ;;
            esac
        done <<EOF
$MASTER_KEY
EOF
    } || {
        while read -r LINE || is_not_empty "${LINE:-}"
        do
            case "${LINE:-}" in
                \#[!#]*)
                    TMP="${TMP:-}#$LINE$LF"
                ;;
                *)
                    TMP="${TMP:-}${LINE:-}$LF"
                ;;
            esac
        done <<EOF
$MASTER_KEY
EOF
    }

    MASTER_KEY="${TMP%"$LF"}"
    SUBKEY="${FIRST_SUBKEY:-}${SUBKEY:+"$LF$SUBKEY"}"
}

enable_next_subkey ()
{
    SUBKEY_TYPE=
    SUBKEY_IS_ADDITIONAL=
    TMP=

    while read -r LINE || is_not_empty "${LINE:-}"
    do
        TEST_KEY_SETTINGS="${TEST_KEY_SETTINGS#"$LINE"}"
        TEST_KEY_SETTINGS="${TEST_KEY_SETTINGS#"$LF"}"

        is_not_empty "${SUBKEY_IS_ADDITIONAL:-}" ||
        case "${LINE:-}" in
            Expire-Date:* | Subkey-Type:* | Subkey-Curve:* | Subkey-Length:* | Subkey-Usage:*)
                LINE="#$LINE"
            ;;
            \##Subkey-Type:*)
                is_empty "${SUBKEY_TYPE:-}" && {
                    LINE="${LINE#??}"
                    SUBKEY_TYPE=1
                } || {
                    TMP="${TMP:-}${LINE:-}$LF"
                    break
                }
            ;;
            \##Expire-Date:* | \##Subkey-Curve:* | \##Subkey-Length:* | \##Subkey-Usage:*)
                LINE="${LINE#??}"
            ;;
        esac
        TMP="${TMP:-}${LINE:-}$LF"
    done <<EOF
$TEST_KEY_SETTINGS
EOF

    TEST_KEY_SETTINGS="$TMP$TEST_KEY_SETTINGS"
}

check_key_settings ()
{
    while :
    do
        KEY_SETTINGS="${CANVAS:-}$TEST_KEY_SETTINGS"
        gpg_generate_key --homedir "$TMP_GNUPGHOME" --dry-run || return
        case "$TEST_KEY_SETTINGS" in
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
    done <<EOF
$MASTER_KEY
EOF
}

set_protection ()
{
    case "${STDIN_PASSPHRASE:-}" in
        "")
            is_empty "${NO_PROTECTION:-}" || {
                PASSPHRASE=
                KEY_SETTINGS="$KEY_SETTINGS$LF%no-protection"
            }
        ;;
        "$LF")
            is_empty "${KEY_TYPE:-"${SUBKEY_TYPE:-}"}" || {
                PASSPHRASE=
                KEY_SETTINGS="$KEY_SETTINGS$LF%no-protection"
                NO_PROTECTION=yes
            }
        ;;
        *)
            is_not_empty "${PASSPHRASE:-}" || {
                is_empty "${KEY_TYPE:-"${SUBKEY_TYPE:-}"}" || {
                    PASSPHRASE="$STDIN_PASSPHRASE"
                    KEY_SETTINGS="$KEY_SETTINGS${LF}Passphrase: ${PASSPHRASE:-}"
                }
            }
            NO_PROTECTION=
        ;;
    esac
}

format_error_message_with_line_num ()
{
    GPG_RETURN_CODE=$?
    TMP=

    while read -r LINE || is_not_empty "${LINE:-}"
    do
        case "${LINE:-}" in
            "gpg: -:"[0-9]*)
                LINE="${LINE#"gpg: -:"}"
                LINE_NUM="${LINE%%:*}"
                TMP="${TMP:-}gpg: $BATCH_FILE:$((LINE_NUM - 1)):${LINE#*:}$LF"
            ;;
            "gpg: -:"*)
                LINE="${LINE#"gpg: -:"}"
                TMP="${TMP:-}gpg: $BATCH_FILE:${LINE:-}$LF"
            ;;
            *)
                TMP="${TMP:-}${LINE:-}$LF"
            ;;
        esac
    done <<EOF
$STATUS
EOF

    STATUS="${TMP%"$LF"}"
    return "$GPG_RETURN_CODE"
}

format_error_message ()
{
    GPG_RETURN_CODE=$?
    TMP=

    while read -r LINE || is_not_empty "${LINE:-}"
    do
        case "${LINE:-}" in
            "gpg: -:"*)
                LINE="${LINE#"gpg: -:"}"
                TMP="${TMP:-}gpg: $BATCH_FILE:${LINE:-}$LF"
            ;;
            *)
                TMP="${TMP:-}${LINE:-}$LF"
            ;;
        esac
    done <<EOF
$STATUS
EOF

    STATUS="${TMP%"$LF"}"
    return "$GPG_RETURN_CODE"
}

generate_key ()
{
    MASTER_KEY="${MASTER_KEY%"$LF"}"
    include_subkey
    is_empty "${VERBOSE:-}" || say -n "checking the GPG key parameters:"
    TEST_KEY_SETTINGS="$MASTER_KEY$LF%no-protection"
    if is_not_empty "${GPG_EDIT_KEY_ID:-}"
    then
        is_not_empty "${NAME_REAL:-}" || TEST_KEY_SETTINGS="$TEST_KEY_SETTINGS${LF}Name-Real: $PKG"
        if is_empty "${KEY_TYPE:-}"
        then
            TEST_KEY_SETTINGS="Key-Type: 1$LF$TEST_KEY_SETTINGS"
            STATUS="$(check_key_settings)" || format_error_message_with_line_num
        else
            STATUS="$(check_key_settings)" || format_error_message
        fi && {
            KEY_ID="${GPG_EDIT_KEY_ID:-}"
            is_empty "${VERBOSE:-}" || echo " passed"
            set_protection
            extend_canvas
        }
    else
        STATUS="$(check_key_settings)" || format_error_message && {
            KEY_SETTINGS="${CANVAS:-}$MASTER_KEY"
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
        GPG_RETURN_CODE=$?
        extend_canvas
        is_empty "${VERBOSE:-}" &&  echo "${STATUS:-}" ||
                                    echo " failed${STATUS:+"$LF$STATUS"}"
    }
    set_key_variables
}

set_key_variables ()
{
    MASTER_KEY=
    KEY_TYPE=
    SUBKEY=
    SUBKEY_TYPE=
    SUBKEY_LENGTH=
    SUBKEY_CURVE=
    SUBKEY_USAGE=
    FIRST_SUBKEY=
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
    set_key_variables
    while read -r KEYWORD || is_not_empty "${KEYWORD:-}"
    do
        case "${KEYWORD:-}" in
            \#*)
                KEYWORD=
            ;;
            %commit)
                generate_key
                KEYWORD=
            ;;
            %no-protection)
                NO_PROTECTION=yes
                KEYWORD=
            ;;
            Key-Type:*)
                is_empty "${KEY_TYPE:-}" && KEY_TYPE="$KEYWORD" || generate_key
            ;;
            Expire-Date:*)
                is_empty "${EXPIRE_DATE:-}" &&
                EXPIRE_DATE="${KEYWORD##*[[:blank:]]}" || {
                    EXPIRE_DATE_IS_ADDITIONAL=yes
                    is_empty "${SUBKEY_IS_ADDITIONAL:-}" && {
                        FIRST_SUBKEY="${FIRST_SUBKEY:+"$FIRST_SUBKEY$LF"}$KEYWORD"
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
                    FIRST_SUBKEY="${FIRST_SUBKEY:+"$FIRST_SUBKEY$LF"}$KEYWORD"
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
                    FIRST_SUBKEY="${FIRST_SUBKEY:+"$FIRST_SUBKEY$LF"}$KEYWORD"
                    KEYWORD="#$KEYWORD"
                } || {
                    SUBKEY="${SUBKEY:+"$SUBKEY$LF"}$KEYWORD"
                    KEYWORD="##$KEYWORD"
                }
            ;;
        esac
        MASTER_KEY="${MASTER_KEY:-}${KEYWORD:-}$LF"
    done < "$BATCH_FILE"
    is_empty "${MASTER_KEY:-"${SUBKEY:-}"}" && return || generate_key
}

check_dependencies ()
{
    is_not_empty "${GPG:-}" || die   "gpg: command not found"
     DATE="$(which date)"   || die  "date: command not found"
    MKDIR="$(which mkdir)"  || die "mkdir: command not found"
       RM="$(which rm)"     || die    "rm: command not found"
}

main ()
{
    GPG="$(which gpg)"      || GPG=
    is_empty "${HELP:-}"    || show_help
    is_empty "${VERSION:-}" || show_version

    check_dependencies
    is_empty "${OPTIONS_FILE:-}" || can_read_file "$OPTIONS_FILE" || try
    is_empty  "${GNUPGHOME:-}" || {
        is_dir "$GNUPGHOME" || try 2 "no such directory: -- '$GNUPGHOME'"
        export   GNUPGHOME
    }
    is_empty "${GPG_EDIT_KEY_ID:-}" ||
        >/dev/null 2>&1 run_gpg --list-keys "$GPG_EDIT_KEY_ID" ||
            try "key not found: -- '$GPG_EDIT_KEY_ID'"

    is_diff $# 0 || try 2 "no batch file specified"
    TMP_GNUPGHOME="${TMP_GNUPGHOME:-"$(mktempdir)"}" || die "$TMP_GNUPGHOME"
    for BATCH_FILE in "$@"
    do
        can_read_file "${BATCH_FILE:-}" || {
            GPG_RETURN_CODE=$?
            break
        }
        run_batch_file
    done
    gpg_update_trustdb
    is_empty "${KEY_CREATED:+"${VERBOSE:-}"}" || say 0 "key created: $KEY_CREATED"
    STATUS="$(2>&1 "$RM" -rvf -- "$TMP_GNUPGHOME")" || die "[TMP_GNUPGHOME] $STATUS"
    return "${GPG_RETURN_CODE:-0}"
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
        try 2 "$PREFIX: option requires an argument -- '$1'"
}

invalid_option ()
{
    is_equal "${#1}" 2 &&
    try 2 "$PREFIX: invalid option -- '${1#?}'" ||
    try 2 "$PREFIX: unrecognized option '$1'"
}

ARG_NUM=0
while is_diff $# 0
do
    ARG_NUM=$((ARG_NUM + 1))
    PREFIX="${ARG_NUM}th argument"
    case "${1:-}" in
        -[?h] | --help)
            HELP="$1"
        ;;
        -[?h]*)
            HELP="${1%"${1#??}"}"
            ARG="-${1#??}"
            shift
            set -- '' "$ARG" "$@"
        ;;
        --version)
            VERSION="$1"
        ;;
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
            ARG_NUM="$((ARG_NUM + 1))" OPTIONS_FILE="$2"
            shift
        ;;
        --options=*)
            arg_is_not_empty "${1%%=*}" "${1#*=}"
            OPTIONS_FILE="${1#*=}"
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
