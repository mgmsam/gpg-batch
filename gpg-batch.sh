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
Usage: $PACKAGE_NAME [OPTION] [--] BATCHFILE ...
   or: $PACKAGE_NAME [OPTION] --edit-key <key-ID> [--] BATCHFILE ..."
}

show_help ()
{
    is_empty "${GPG_BIN:-}" && >&2 say "gpg: command not found" || "$GPG_BIN" --version
    usage
    echo "
Commands:
      --edit-key <key-ID>   edit a key

Options:
      --allow-weak-key-signatures
                            To avoid a minor risk of collision attacks on third-
                            party key signatures made using SHA-1, those key
                            signatures are considered invalid. This options
                            allows one to override this restriction.
      --force               After detection of errors, continue execution.
      --homedir dir         Set the name of the home directory to dir. If this
                            option is not used, the home directory defaults to
                            ‘~/.gnupg’. It is only recognized when given on the
                            command line. It also overrides any home directory
                            stated through the environment variable ‘GNUPGHOME’
                            or (on Windows systems) by means of the Registry
                            entry HKCU\Software\GNU\GnuPG:HomeDir.
      --passphrase string   Use string as the passphrase.
      --passphrase-fd n     Read the passphrase from file descriptor n. Only the
                            first line will be read from file descriptor n.
      --passphrase-file file
                            Read the passphrase from file. Only the first line
                            will be read from file.
      --pinentry-mode mode  Set the pinentry mode to mode. Allowed values for
                            mode are:
                              default
                                     Use the default of the agent, which is ask.
                              ask    Force the use of the Pinentry.
                              cancel Emulate use of Pinentry's cancel button.
                              error  Return a Pinentry error ('No Pinentry').
                              loopback
                                     Redirect Pinentry queries to the caller.
                                     Note that in contrast to Pinentry the user
                                     is not prompted again if he enters a bad
                                     password.
      --version             Display version information and exit.
  -h, -?, --help            Display this help and exit.

Options controlling the diagnostic output:
  -v, --verbose             Verbose.
  -q, --quiet               Be somewhat more quiet.
      --options FILE        Read options from FILE.
      --no-tty              Make sure that the TTY (terminal) is never used for
                            any output. This option is needed in some cases
                            because GnuPG sometimes prints warnings to the TTY
                            even if --batch is used.

An argument of '--' disables further option processing.

Report bugs to: bug-$PACKAGE_NAME@mgmsam.pro
$PACKAGE_NAME home page: <https://www.mgmsam.pro/shell-script/$PACKAGE_NAME/>"
    exit
}

show_version ()
{
    echo "${0##*/} 0.1.1 - (C) 06.12.2025

Written by Mironov A Semyon
Site       www.mgmsam.pro
Email      s.mironov@mgmsam.pro"
    exit
}

try ()
{
    say "$@" >&2
    echo "Try '$PACKAGE_NAME --help' for more information." >&2
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
            *[!0-9]* | "")
                break
            ;;
            *)
                RETURN=$1
            ;;
        esac
        shift
    done
    is_empty "$@" || {
        puts "$PACKAGE_NAME:${1:+" $@"}"
        PUTS_OPTIONS=
    }
}

die ()
{
    say "$@" >&2
    exit "$RETURN"
}

verbose_say ()
{
    is_empty "${VERBOSE:-}" || say "$@"
}

verbose_echo ()
{
    is_empty "${VERBOSE:-}" || echo "$@"
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
        ;;
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
        TMPTRG="$TMPDIR/${PACKAGE_NAME:-tmp}.$(2>/dev/null "$DATE" +%s)"
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

can_read_file ()
{
    is_file "${1:-}" || {
        is_exists "${1:-}" &&
        say 2 "can't open '${1:-}': is not a file" ||
        say 2 "can't open '${1:-}': no such file"
        return 2
    } >&2
    test -r "${1:-}" || {
        say 1 "can't open '${1:-}': no read permissions" >&2
        return 1
    }
}

check_dependencies ()
{
    is_not_empty "${GPG_BIN:-}" || die   "gpg: command not found"
     DATE="$(which date)"       || die  "date: command not found"
    MKDIR="$(which mkdir)"      || die "mkdir: command not found"
       RM="$(which rm)"         || die    "rm: command not found"
}

get_passphrase ()
{
    while IFS="$LF" read -r INPUT_PASSPHRASE ||
            is_not_empty "${INPUT_PASSPHRASE:-}"
    do
        INPUT_PASSPHRASE="${INPUT_PASSPHRASE:-"$LF"}"
        break
    done
}

trim_string ()
{
    STRING="${1#"${1%%[![:space:]]*}"}"
    STRING="${STRING%"${STRING##*[![:space:]]}"}"
    echo "$STRING"
}

get_keyword_value ()
{
    KEYWORD_VALUE="$(trim_string "${1#*[:[:blank:]]}")"
}

set_gpg_options ()
{
    if is_not_empty "${PASSPHRASE_FD:-}"
    then
        is_diff "$PASSPHRASE_FD" 0 || get_passphrase
        GPG_BATCH=gpg_batch_with_passphrase_fd
    elif is_not_empty "${PASSPHRASE_FILE:-}"
    then
        GPG_BATCH=gpg_batch_with_passphrase_file
    elif is_not_empty "${INPUT_PASSPHRASE:-}"
    then
        GPG_BATCH=gpg_batch_with_passphrase
    else
        GPG_BATCH=gpg_batch
    fi

    is_empty "${OPTIONS_FILE:-}" || {
        GPG_OPTIONS="${GPG_OPTIONS:-} --options $OPTIONS_FILE"
        is_not_empty "${PASSPHRASE_FD:-"${PASSPHRASE_FILE:-}"}" || {
            while read -r KEYWORD || is_not_empty "${KEYWORD:-}"
            do
                case "${KEYWORD:-}" in
                    passphrase-fd*)
                        get_keyword_value "$KEYWORD"
                    ;;
                    passphrase-file*)
                        KEYWORD_VALUE=
                    ;;
                esac
            done < "$OPTIONS_FILE"
            is_diff "${KEYWORD_VALUE:-}" 0 || {
                get_passphrase
                PASSPHRASE_FD=0
                GPG_BATCH=gpg_batch_with_passphrase_fd
            }
        }

    }
    GPG_OPTIONS="${GPG_OPTIONS:-} ${ALLOW_WEAK_KEY_SIGNATURES:-} ${PINENTRY_MODE:-} ${NO_TTY:-} ${QUIET:-} ${VERBOSE:-}"
}

set_key_variables ()
{
    MASTER_KEY=
    EXPIRE_DATE=
    KEY_TYPE=
    NAME_REAL=
    SUBKEY_OPTIONS=
    SUBKEY_TYPE=
    SUBKEY_LENGTH=
    SUBKEY_CURVE=
    SUBKEY_USAGE=
    SUBKEY_EXPIRATION_DATE=
    ADDITIONAL_SUBKEY=
    NO_PROTECTION=
    PASSPHRASE=
}

can_generate_subkey_and_master_key_together ()
{
    is_empty "${SUBKEY_EXPIRATION_DATE:+"${SUBKEY_TYPE:-}"}"
}

is_edit_mode ()
{
    is_not_empty "${GPG_EDIT_KEY_ID:-}"
}

run_gpg ()
{
    "$GPG_BIN" --expert --batch ${GPG_OPTIONS:-} "$@"
}

gpg_update_trustdb ()
{
    >/dev/null 2>&1 run_gpg --update-trustdb || :
}

gpg_batch ()
{
    run_gpg "$@" <<EOF
$GPG_KEY_OPTIONS
EOF
}

gpg_batch_with_passphrase ()
{
    run_gpg --pinentry-mode loopback --passphrase "$PASSPHRASE" "$@" <<EOF
$GPG_KEY_OPTIONS
EOF
}

gpg_batch_with_passphrase_fd ()
{
    run_gpg --pinentry-mode loopback --passphrase-fd "$PASSPHRASE_FD" "$@" <<EOF
$GPG_KEY_OPTIONS
EOF
}

gpg_batch_with_passphrase_file ()
{
    run_gpg --pinentry-mode loopback --passphrase-file "$PASSPHRASE_FILE" "$@" <<EOF
$GPG_KEY_OPTIONS
EOF
}

gpg_generate_key ()
{
    "$RUN_GPG_BATCH" --full-generate-key --status-fd=1 "$@"
}

set_subkey_curve ()
{
    case "${SUBKEY_CURVE:-}" in
        [cC][vV]25519)
            SUBKEY_CURVE=0
        ;;
        [eE][dD]25519)
            SUBKEY_CURVE=1
        ;;
        [eE][dD]448)
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
            [aA][uU][tT][hH])
                AUTH=auth
            ;;
            [cC][eE][rR][tT])
                CERT=cert
            ;;
            [eE][nN][cC][rR][yY][pP][tT])
                ENCRYPT=encrypt
            ;;
            [sS][iI][gG][nN])
                SIGN=sign
            ;;
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
        *)
            echo "${1:-}"
            return 1
        ;;
    esac
}

get_subkey_options ()
{
    SUBKEY_TYPE=
    SUBKEY_LENGTH=
    SUBKEY_CURVE=
    SUBKEY_USAGE=
    while read -r LINE || is_not_empty "${LINE:-}"
    do
        case "${LINE:-}" in
            Expire-Date:*)
                get_keyword_value "$LINE"
                EXPIRE_DATE="$KEYWORD_VALUE"
            ;;
            Subkey-Type:*)
                is_empty "${SUBKEY_TYPE:-}" || break
                get_keyword_value "$LINE"
                SUBKEY_TYPE="$KEYWORD_VALUE"
            ;;
            Subkey-Length:*)
                get_keyword_value "$LINE"
                SUBKEY_LENGTH="$KEYWORD_VALUE"
            ;;
            Subkey-Curve:*)
                get_keyword_value "$LINE"
                SUBKEY_CURVE="$KEYWORD_VALUE"
                set_subkey_curve
            ;;
            Subkey-Usage:*)
                get_keyword_value "$LINE"
                SUBKEY_USAGE="$KEYWORD_VALUE"
                set_subkey_usage
            ;;
        esac
        SUBKEY_OPTIONS="${SUBKEY_OPTIONS#"$LINE"}"
        SUBKEY_OPTIONS="${SUBKEY_OPTIONS#"$LF"}"
    done <<EOF
$SUBKEY_OPTIONS
EOF
    SUBKEY_TYPE="$(get_key_type "$SUBKEY_TYPE")"
}

build_subkey_generation_command ()
{
    case "${SUBKEY_TYPE:-}" in
        RSA)
            case "${SUBKEY_USAGE:-}" in
                "" | "auth encrypt sign" | "auth cert encrypt sign")
                    GPG_KEY_OPTIONS="8${LF}A${LF}Q"
                ;;
                "auth sign" | "auth cert sign")
                    GPG_KEY_OPTIONS="8${LF}E${LF}A${LF}Q"
                ;;
                "auth encrypt" | "auth cert encrypt")
                    GPG_KEY_OPTIONS="8${LF}S${LF}A${LF}Q"
                ;;
                "encrypt sign" | "cert encrypt sign")
                    GPG_KEY_OPTIONS="8${LF}Q"
                ;;
                auth | "auth cert")
                    GPG_KEY_OPTIONS="8${LF}S${LF}E${LF}A${LF}Q"
                ;;
                cert)
                    GPG_KEY_OPTIONS="8${LF}S${LF}E${LF}Q"
                ;;
                encrypt | "cert encrypt")
                    GPG_KEY_OPTIONS=6
                ;;
                sign | "cert sign")
                    GPG_KEY_OPTIONS=4
                ;;
            esac
            case "${SUBKEY_LENGTH:-}" in
                "" | *[!0-9]*)
                    SUBKEY_LENGTH=
                ;;
                *)
                    test "$SUBKEY_LENGTH" -ge 1024 &&
                    test "$SUBKEY_LENGTH" -le 4096 || SUBKEY_LENGTH=
                ;;
            esac
            GPG_KEY_OPTIONS="$GPG_KEY_OPTIONS$LF${SUBKEY_LENGTH:-}"
        ;;
        ELG | ELG-E)
            case "${SUBKEY_LENGTH:-}" in
                "" | *[!0-9]*)
                    SUBKEY_LENGTH=
                ;;
                *)
                    test "$SUBKEY_LENGTH" -ge 1024 &&
                    test "$SUBKEY_LENGTH" -le 4096 || SUBKEY_LENGTH=
                ;;
            esac
            GPG_KEY_OPTIONS="5$LF${SUBKEY_LENGTH:-}"
        ;;
        DSA)
            case "${SUBKEY_USAGE:-}" in
                "" | "auth cert sign" | "auth cert" | "auth sign")
                    GPG_KEY_OPTIONS="7${LF}A${LF}Q"
                ;;
                auth)
                    GPG_KEY_OPTIONS="7${LF}S${LF}A${LF}Q"
                ;;
                cert)
                    GPG_KEY_OPTIONS="7${LF}S${LF}Q"
                ;;
                sign)
                    GPG_KEY_OPTIONS=3
                ;;
            esac
            case "${SUBKEY_LENGTH:-}" in
                "" | *[!0-9]*)
                    SUBKEY_LENGTH=
                ;;
                *)
                    test "$SUBKEY_LENGTH" -ge 768  &&
                    test "$SUBKEY_LENGTH" -le 3072 || SUBKEY_LENGTH=
                ;;
            esac
            GPG_KEY_OPTIONS="$GPG_KEY_OPTIONS$LF${SUBKEY_LENGTH:-}"
        ;;
        ECC | ECDH)
            case "$SUBKEY_CURVE" in
                0)
                    SUBKEY_CURVE=1
                ;;
            esac
            GPG_KEY_OPTIONS="12$LF$SUBKEY_CURVE"
        ;;
        ECDSA | EDDSA)
            case "${SUBKEY_USAGE:-}" in
                "" | "auth sign" | "auth cert sign")
                    GPG_KEY_OPTIONS="11${LF}A${LF}Q"
                ;;
                cert)
                    GPG_KEY_OPTIONS="11${LF}S${LF}Q"
                ;;
                auth | "auth cert")
                    GPG_KEY_OPTIONS="11${LF}S${LF}A${LF}Q"
                ;;
                sign | "cert sign")
                    GPG_KEY_OPTIONS=10
                ;;
            esac
            GPG_KEY_OPTIONS="$GPG_KEY_OPTIONS$LF$SUBKEY_CURVE"
        ;;
    esac

    GPG_KEY_OPTIONS="addkey$LF$GPG_KEY_OPTIONS$LF${EXPIRE_DATE:-}$LF${NO_PROTECTION:+y$LF}save"
   #GPG_KEY_OPTIONS="addkey$LF$GPG_KEY_OPTIONS$LF${EXPIRE_DATE:-}${LF}save"

    is_diff "$GPG_BATCH" gpg_batch_with_passphrase_fd ||
        GPG_KEY_OPTIONS="$INPUT_PASSPHRASE$LF$GPG_KEY_OPTIONS"
}

gpg_generate_subkey ()
{
    while is_not_empty "${SUBKEY_OPTIONS:-}"
    do
        get_subkey_options
        build_subkey_generation_command

        verbose_say "generating the GPG subkey [$SUBKEY_TYPE]: ..."
        if "$RUN_GPG_BATCH" --command-fd=0 --edit-key "$KEY_ID"
        then
            verbose_say "generating the GPG subkey [$SUBKEY_TYPE]: success"
        else
            GPG_RETURN_CODE=$?
            verbose_say "generating the GPG subkey [$SUBKEY_TYPE]: failed"
            return "$GPG_RETURN_CODE"
        fi
    done
}

include_subkey ()
{
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
}

exclude_subkey ()
{
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

build_key_chain ()
{
    TMP=
    can_generate_subkey_and_master_key_together && {
        is_edit_mode || SUBKEY_OPTIONS=
        include_subkey
    } || exclude_subkey
    MASTER_KEY="${TMP%"$LF"}"
    SUBKEY_OPTIONS="${SUBKEY_OPTIONS:-}${ADDITIONAL_SUBKEY:+"$LF$ADDITIONAL_SUBKEY"}"
}

set_protection ()
{
    GPG_KEY_OPTIONS="$MASTER_KEY"
    if is_empty "${KEY_TYPE:-"${SUBKEY_TYPE:-}"}"
    then
        RUN_GPG_BATCH=gpg_batch
    elif is_empty "${PASSPHRASE:-"${NO_PROTECTION:-}"}"
    then
        RUN_GPG_BATCH="$GPG_BATCH"
        case "${INPUT_PASSPHRASE:-}" in
            "$LF")
                NO_PROTECTION=yes
                GPG_KEY_OPTIONS="$GPG_KEY_OPTIONS$LF%no-protection"
            ;;
            ?*)
                is_equal "$GPG_BATCH" gpg_batch_with_passphrase_fd &&
                GPG_KEY_OPTIONS="$INPUT_PASSPHRASE$LF$GPG_KEY_OPTIONS"
                PASSPHRASE="$INPUT_PASSPHRASE"
            ;;
        esac
    else
        RUN_GPG_BATCH=gpg_batch
    fi
}

include_next_subkey ()
{
    SUBKEY_TYPE=
    SUBKEY_IS_ADDITIONAL=
    TMP=

    while read -r LINE || is_not_empty "${LINE:-}"
    do
        GPG_TEST_KEY_OPTIONS="${GPG_TEST_KEY_OPTIONS#"$LINE"}"
        GPG_TEST_KEY_OPTIONS="${GPG_TEST_KEY_OPTIONS#"$LF"}"

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
$GPG_TEST_KEY_OPTIONS
EOF

    GPG_TEST_KEY_OPTIONS="$TMP$GPG_TEST_KEY_OPTIONS"
}

check_key_options ()
{
    while :
    do
        GPG_KEY_OPTIONS="${CANVAS:-}$GPG_TEST_KEY_OPTIONS"
        gpg_generate_key --homedir "$TMP_GNUPGHOME" --dry-run || return
        case "$GPG_TEST_KEY_OPTIONS" in
            *$LF##*)
                include_next_subkey
            ;;
            *)
                return
            ;;
        esac
    done 2>&1 >/dev/null
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

extend_canvas ()
{
    while read -r LINE || is_not_empty "${LINE:-}"
    do
        CANVAS="${CANVAS:-}$LF"
    done <<EOF
$MASTER_KEY
EOF
}

generate_key ()
{
    MASTER_KEY="${MASTER_KEY%"$LF"}"
    build_key_chain
    set_protection
    verbose_say -n "testing the GPG key parameters:"
    GPG_TEST_KEY_OPTIONS="$GPG_KEY_OPTIONS$LF%no-protection"
    if is_edit_mode
    then
        is_not_empty "${NAME_REAL:-}" ||
            GPG_TEST_KEY_OPTIONS="$GPG_TEST_KEY_OPTIONS${LF}Name-Real: $PACKAGE_NAME"
        if is_empty "${KEY_TYPE:-}"
        then
            GPG_TEST_KEY_OPTIONS="Key-Type: 1$LF$GPG_TEST_KEY_OPTIONS"
            STATUS="$(check_key_options)" || format_error_message_with_line_num
        else
            STATUS="$(check_key_options)" || format_error_message
        fi && {
            KEY_ID="${GPG_EDIT_KEY_ID:-}"
            extend_canvas
            verbose_echo " passed"
        }
    else
        STATUS="$(check_key_options)" || format_error_message && {
            verbose_echo " passed"
            verbose_say "generating the GPG key [$KEY_TYPE]: ..."
            gpg_update_trustdb
            GPG_KEY_OPTIONS="${CANVAS:-}$GPG_KEY_OPTIONS"
            STATUS="$(gpg_generate_key)" || {
                GPG_RETURN_CODE=$?
                false
            } && {
                KEY_ID="${STATUS##*KEY_CREATED}"
                KEY_ID="${KEY_ID##*[[:blank:]]}"
                KEY_CREATED="${KEY_CREATED:+"$KEY_CREATED "}$KEY_ID"
                extend_canvas
                verbose_say "generating the GPG key [$KEY_TYPE]: success"
            }
        }
    fi &&
    case "${SUBKEY_OPTIONS:-}" in
        ?*)
            gpg_update_trustdb
            gpg_generate_subkey || is_not_empty "${FORCE:-}" || return
        ;;
    esac || {
        verbose_echo " failed"
        echo "${STATUS:-}"
        is_not_empty "${FORCE:-}" || return
        extend_canvas
    }
    set_key_variables
}

check_expiration_date ()
{
    case "${KEYWORD_VALUE:-}" in
        *[dD])
            KEYWORD_VALUE="${KEYWORD_VALUE%?}d"
        ;;
        *[mM])
            KEYWORD_VALUE="${KEYWORD_VALUE%?}m"
        ;;
        *[wW])
            KEYWORD_VALUE="${KEYWORD_VALUE%?}w"
        ;;
        *[yY])
            KEYWORD_VALUE="${KEYWORD_VALUE%?}y"
        ;;
        *[!0-9]*)
            return 2
        ;;
        *)
            KEYWORD_VALUE="${KEYWORD_VALUE:-}d"
        ;;
    esac &&
    case "${KEYWORD_VALUE%?}" in
        "" | *[!0-9]*)
            return 2
        ;;
    esac
}

set_expiration_date ()
{
    if is_empty "${EXPIRE_DATE:-}"
    then
        EXPIRE_DATE="$KEYWORD_VALUE"
    else
        if is_not_empty "${ADDITIONAL_SUBKEY:-}"
        then
            ADDITIONAL_SUBKEY="$ADDITIONAL_SUBKEY$LF$KEYWORD"
            KEYWORD="##$KEYWORD"
        elif is_not_empty "${SUBKEY_OPTIONS:-}"
        then
            if is_equal "$EXPIRE_DATE" "$KEYWORD_VALUE"
            then
                KEYWORD=
            else
                SUBKEY_EXPIRATION_DATE=yes
                SUBKEY_OPTIONS="$SUBKEY_OPTIONS$LF$KEYWORD"
                KEYWORD="#$KEYWORD"
            fi
        else
            SUBKEY_OPTIONS="$KEYWORD"
            KEYWORD="#$KEYWORD"
        fi
    fi
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
                generate_key || return
                KEYWORD=
            ;;
            %no-protection)
                NO_PROTECTION=yes
            ;;
            Expire-Date:*)
                get_keyword_value "$KEYWORD"
                if check_expiration_date
                then
                    set_expiration_date
                fi
            ;;
            Key-Type:*)
                is_empty "${KEY_TYPE:-}" || generate_key || return
                get_keyword_value "$KEYWORD"
                KEY_TYPE="$(get_key_type "${KEYWORD_VALUE:-}")" &&
                    KEY_TYPE="$KEYWORD_VALUE" || KEY_TYPE="$KEYWORD"
            ;;
            Name-Real:*)
                NAME_REAL=1
            ;;
            Passphrase:*)
                get_keyword_value "$KEYWORD"
                PASSPHRASE="${KEYWORD_VALUE:-}"
            ;;
            Subkey-Type:*)
                is_empty "${SUBKEY_TYPE:-}" && {
                    SUBKEY_OPTIONS="${SUBKEY_OPTIONS:+"$SUBKEY_OPTIONS$LF"}$KEYWORD"
                    SUBKEY_TYPE=1
                    KEYWORD="#$KEYWORD"
                } || {
                    ADDITIONAL_SUBKEY="$ADDITIONAL_SUBKEY$LF$KEYWORD"
                    KEYWORD="##$KEYWORD"
                }
            ;;
            Subkey-Curve:* | Subkey-Length:* | Subkey-Usage:*)
                is_empty "${ADDITIONAL_SUBKEY:-}" && {
                    SUBKEY_OPTIONS="${SUBKEY_OPTIONS:+"$SUBKEY_OPTIONS$LF"}$KEYWORD"
                    KEYWORD="#$KEYWORD"
                } || {
                    ADDITIONAL_SUBKEY="$ADDITIONAL_SUBKEY$LF$KEYWORD"
                    KEYWORD="##$KEYWORD"
                }
            ;;
        esac
        MASTER_KEY="${MASTER_KEY:-}${KEYWORD:-}$LF"
    done < "$BATCH_FILE"
    is_empty "${MASTER_KEY:-"${SUBKEY_OPTIONS:-}"}" && return || generate_key
}

arg_is_not_empty ()
{
    is_not_empty "${2:-}"  || {
        is_equal "${#1}" 2 &&
        try 2 "$PREFIX: option requires an argument -- '${1#?}'" ||
        try 2 "$PREFIX: option '$1' requires an argument"
    }
}

invalid_option ()
{
    is_equal "${#1}" 2 &&
    try 2 "$PREFIX: invalid option -- '${1#?}'" ||
    try 2 "$PREFIX: unrecognized option '$1'"
}

is_not_option ()
{
    for OPTION in $OPTIONS
    do
        case "$2" in
            "--$OPTION" | "-$OPTION")
                arg_is_not_empty "$1"
            ;;
        esac
    done
}

set_pinentry_mode ()
{
    case "${2:-}" in
        ask | cancel | default | error | loopback)
            PINENTRY_MODE="--pinentry-mode $2"
        ;;
        "")
            arg_is_not_empty "$1"
        ;;
        -*)
            is_not_option "$1" "$2"
            die 2 "invalid pinentry mode '$2'"
        ;;
    esac
}

PACKAGE_NAME="${0##*/}"
LF='
'
OPTIONS="? h help version allow-weak-key-signatures force edit-key homedir no-tty options passphrase pinentry-mode q quiet v verbose --"
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
        --allow-weak-key-signatures)
            ALLOW_WEAK_KEY_SIGNATURES="$1"
        ;;
        --force)
            FORCE="$1"
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
        --passphrase)
            arg_is_not_empty "$1" "${2+"is set"}"
            is_empty "${2:-}" && INPUT_PASSPHRASE="$LF" || {
                is_not_option "$1" "$2"
                INPUT_PASSPHRASE="$2"
            }
            ARG_NUM="$((ARG_NUM + 1))"
            shift
        ;;
        --passphrase=*)
            INPUT_PASSPHRASE="${1#*=}"
            INPUT_PASSPHRASE="${INPUT_PASSPHRASE:-"$LF"}"
        ;;
        --passphrase-fd)
            arg_is_not_empty "$1" "${2:-}"
            ARG_NUM="$((ARG_NUM + 1))"
            PASSPHRASE_FD="$2"
            PASSPHRASE_FILE=
            shift
        ;;
        --passphrase-fd=*)
            arg_is_not_empty "${1%%=*}" "${1#*=}"
            PASSPHRASE_FD="${1#*=}"
            PASSPHRASE_FILE=
        ;;
        --passphrase-file)
            arg_is_not_empty "$1" "${2:-}"
            ARG_NUM="$((ARG_NUM + 1))"
            PASSPHRASE_FD=
            PASSPHRASE_FILE="$2"
            shift
        ;;
        --passphrase-file=*)
            arg_is_not_empty "${1%%=*}" "${1#*=}"
            PASSPHRASE_FD=
            PASSPHRASE_FILE="${1#*=}"
        ;;
        --pinentry-mode)
            set_pinentry_mode "$1" "$2"
            ARG_NUM="$((ARG_NUM + 1))"
            shift
        ;;
        --pinentry-mode=*)
            set_pinentry_mode "${1%%=*}" "${1#*=}"
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

GPG_BIN="$(which gpg)"  || GPG_BIN=
is_empty "${HELP:-}"    || show_help
is_empty "${VERSION:-}" || show_version

check_dependencies
is_empty  "${GNUPGHOME:-}" || {
    is_dir "$GNUPGHOME" || try 2 "no such directory: -- '$GNUPGHOME'"
    export   GNUPGHOME
}

if is_edit_mode
then
    STATUS="$(2>&1 run_gpg --list-keys "$GPG_EDIT_KEY_ID")" || {
        GPG_RETURN_CODE=$?
        >&2 echo "${STATUS:-}"
        die "$GPG_RETURN_CODE"
    }
fi

is_diff $# 0 || try 2 "no batch file specified"
TMP_GNUPGHOME="${TMP_GNUPGHOME:-"$(mktempdir)"}" || die "$TMP_GNUPGHOME"

set_gpg_options
for BATCH_FILE in "$@"
do
    can_read_file "${BATCH_FILE:-}" || {
        GPG_RETURN_CODE=$?
        is_not_empty "${FORCE:-}" || break
        continue
    }
    run_batch_file || break
done
gpg_update_trustdb
is_empty "${KEY_CREATED:+"${VERBOSE:-}"}" || say 0 "key created: $KEY_CREATED"
STATUS="$(2>&1 "$RM" -rvf -- "$TMP_GNUPGHOME")" || die "[TMP_GNUPGHOME] $STATUS"
exit "${GPG_RETURN_CODE:-0}"
