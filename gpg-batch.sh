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

Report bugs to: bug-$PKG@mgmsam.pro
$PKG home page: <https://www.mgmsam.pro/shell-script/$PKG/>"
    exit
}

show_version ()
{
    echo "${0##*/} 0.1.0 - (C) 13.09.2025

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

trim_string ()
{
    STRING="${1#"${1%%[![:space:]]*}"}"
    STRING="${STRING%"${STRING##*[![:space:]]}"}"
    echo "$STRING"
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
    "$GPG" ${OPTIONS_FILE:+--options "$OPTIONS_FILE"} ${GPG_OPTIONS:-} "$@"
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

get_keyword_value ()
{
    KEYWORD_VALUE="$(trim_string "${1#*:}")"
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
            case "${SUBKEY_LENGTH:-}" in
                "" | *[!0-9]*)
                    SUBKEY_LENGTH=
                ;;
                *)
                    test "$SUBKEY_LENGTH" -ge 1024 &&
                    test "$SUBKEY_LENGTH" -le 4096 || SUBKEY_LENGTH=
                ;;
            esac
            KEY_SETTINGS="$KEY_SETTINGS$LF${SUBKEY_LENGTH:-}"
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
            case "${SUBKEY_LENGTH:-}" in
                "" | *[!0-9]*)
                    SUBKEY_LENGTH=
                ;;
                *)
                    test "$SUBKEY_LENGTH" -ge 768  &&
                    test "$SUBKEY_LENGTH" -le 3072 || SUBKEY_LENGTH=
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
                "" | "auth sign" | "auth cert sign")
                    KEY_SETTINGS="11${LF}A${LF}Q"
                ;;
                cert)
                    KEY_SETTINGS="11${LF}S${LF}Q"
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
    while is_not_empty "${SUBKEY:-}"
    do
        get_subkey_settings
        build_subkey_generation_command

        is_empty "${VERBOSE:-}" ||
             say "generating the GPG subkey [$SUBKEY_TYPE]: ..."

        if gpg_edit_key
        then
            is_empty "${VERBOSE:-}" ||
                 say "generating the GPG subkey [$SUBKEY_TYPE]: success"
        else
            is_empty "${VERBOSE:-}" ||
                 say "generating the GPG subkey [$SUBKEY_TYPE]: failed"
            return "$GPG_RETURN_CODE"
        fi
    done
}

can_generate_subkey_and_master_key_together ()
{
    is_empty "${SUBKEY_EXPIRATION_DATE:+"${SUBKEY_TYPE:-}"}"
}

is_edit_mode ()
{
    is_not_empty "${GPG_EDIT_KEY_ID:-}"
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
        is_edit_mode || SUBKEY=
        include_subkey
    } || exclude_subkey

    MASTER_KEY="${TMP%"$LF"}"
    SUBKEY="${SUBKEY:-}${ADDITIONAL_SUBKEY:+"$LF$ADDITIONAL_SUBKEY"}"
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
    build_key_chain
    is_empty "${VERBOSE:-}" || say -n "testing the GPG key parameters:"
    TEST_KEY_SETTINGS="$MASTER_KEY$LF%no-protection"
    if is_edit_mode
    then
        is_not_empty "${NAME_REAL:-}" ||
            TEST_KEY_SETTINGS="$TEST_KEY_SETTINGS${LF}Name-Real: $PKG"
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
            is_empty "${VERBOSE:-}" || {
                KEY_TYPE="$(trim_string "${KEY_TYPE#*:}")"
                KEY_TYPE="$(get_key_type "$KEY_TYPE")"
                say "generating the GPG key [$KEY_TYPE]: ..."
            }
            STATUS="$(gpg_generate_key)" || {
                GPG_RETURN_CODE=$?
                false
            } && {
                extend_canvas
                KEY_ID="${STATUS##*KEY_CREATED}"
                KEY_ID="${KEY_ID##*[[:blank:]]}"
                KEY_CREATED="${KEY_CREATED:+"$KEY_CREATED "}$KEY_ID"
                is_empty "${VERBOSE:-}" ||
                    say "generating the GPG key [$KEY_TYPE]: success"
            }
        }
    fi &&
    case "${SUBKEY:-}" in
        ?*)
            gpg_update_trustdb
            gpg_generate_subkey || is_not_empty "${FORCE:-}" || return
        ;;
    esac || {
        is_empty "${VERBOSE:-}" &&  echo "${STATUS:-}" ||
                                    echo " failed${STATUS:+"$LF$STATUS"}"
        is_not_empty "${FORCE:-}" || return
        extend_canvas
    }
    set_key_variables
}

set_key_variables ()
{
    MASTER_KEY=
    EXPIRE_DATE=
    KEY_TYPE=
    NAME_REAL=
    SUBKEY=
    SUBKEY_TYPE=
    SUBKEY_LENGTH=
    SUBKEY_CURVE=
    SUBKEY_USAGE=
    SUBKEY_EXPIRATION_DATE=
    ADDITIONAL_SUBKEY=
    SYNTAX_ERROR=
    NO_PROTECTION=
    PASSPHRASE=
}

check_expiration_date ()
{
    case "$KEYWORD_VALUE" in
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
            SYNTAX_ERROR=yes
            return 2
        ;;
        *)
            KEYWORD_VALUE="${KEYWORD_VALUE}d"
        ;;
    esac &&
    case "${KEYWORD_VALUE%?}" in
        "" | *[!0-9]*)
            SYNTAX_ERROR=yes
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
        elif is_not_empty "${SUBKEY:-}"
        then
            if is_equal "$EXPIRE_DATE" "$KEYWORD_VALUE"
            then
                KEYWORD=
            else
                SUBKEY_EXPIRATION_DATE=yes
                SUBKEY="$SUBKEY$LF$KEYWORD"
                KEYWORD="#$KEYWORD"
            fi
        else
            SUBKEY="$KEYWORD"
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
                KEYWORD=
            ;;
            Expire-Date:*)
                is_not_empty "${SYNTAX_ERROR:-}" || {
                    get_keyword_value "$KEYWORD"
                    is_empty "${KEYWORD_VALUE:-}" && SYNTAX_ERROR=yes ||
                    if check_expiration_date
                    then
                        set_expiration_date
                    fi
                }
            ;;
            Key-Type:*)
                is_empty "${KEY_TYPE:-}" || generate_key || return
                KEY_TYPE="$KEYWORD"
            ;;
            Name-Real:*)
                NAME_REAL=1
            ;;
            Passphrase:*)
                is_not_empty "${SYNTAX_ERROR:-}" || {
                    get_keyword_value "$KEYWORD"
                    is_empty "${KEYWORD_VALUE:-}" && SYNTAX_ERROR=yes ||
                    case "${STDIN_PASSPHRASE:-}" in
                        "")
                            PASSPHRASE="$KEYWORD_VALUE"
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
                    SUBKEY="${SUBKEY:+"$SUBKEY$LF"}$KEYWORD"
                    SUBKEY_TYPE=1
                    KEYWORD="#$KEYWORD"
                } || {
                    ADDITIONAL_SUBKEY="$ADDITIONAL_SUBKEY$LF$KEYWORD"
                    KEYWORD="##$KEYWORD"
                }
            ;;
            Subkey-Curve:* | Subkey-Length:* | Subkey-Usage:*)
                is_empty "${ADDITIONAL_SUBKEY:-}" && {
                    SUBKEY="${SUBKEY:+"$SUBKEY$LF"}$KEYWORD"
                    KEYWORD="#$KEYWORD"
                } || {
                    ADDITIONAL_SUBKEY="$ADDITIONAL_SUBKEY$LF$KEYWORD"
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

    if is_edit_mode
    then
        STATUS="$(2>&1 run_gpg --list-keys "$GPG_EDIT_KEY_ID")" || {
            GPG_RETURN_CODE=$?
            >&2 echo "${STATUS:-}"
            return "$GPG_RETURN_CODE"
        }
    fi

    is_diff $# 0 || try 2 "no batch file specified"
    TMP_GNUPGHOME="${TMP_GNUPGHOME:-"$(mktempdir)"}" || die "$TMP_GNUPGHOME"
    GPG_OPTIONS="${ALLOW_WEAK_KEY_SIGNATURES:-} ${NO_TTY:-} ${QUIET:-} ${VERBOSE:-}"
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
