#!/bin/sh
# -*- Mode: sh; sh-indentation: 4; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# vim:ft=zsh:sw=4:sts=4:et
#
# Copyright (c) 2017 Sebastian Gniazdowski
# All rights reserved.

#
# Setup
#

# /bin/sh stage, load configuration to obtain $zsh_control_bin {{{
SH_ZERO_DIR=${0%/zsh-valgrind-parse.cmd} # this barely works

[ -z "$ZSHV_TCONF_FILE" ] && ZSHV_TCONF_FILE="vtest.conf"
[ "$1" != "${1#conf:}" ] && { ZSHV_TCONF_FILE="${1#conf:}"; shift; }

if [ -n "$ZSHV_TCONF_DIR" ]; then
    . "${ZSHV_TCONF_DIR}/${ZSHV_TCONF_FILE}"
elif [ -f "${SH_ZERO_DIR}/${ZSHV_TCONF_FILE}" ]; then
    . "${SH_ZERO_DIR}/${ZSHV_TCONF_FILE}"
elif [ -f "${PWD}/${ZSHV_TCONF_FILE}" ]; then
    . "${PWD}/${ZSHV_TCONF_FILE}"
elif [ -f "VATS/${ZSHV_TCONF_FILE}" ]; then
    . "VATS/${ZSHV_TCONF_FILE}"
else
    echo "Couldn't find ${ZSHV_TCONF_FILE} (searched paths: \$ZSHV_TCONF_DIR=\`$ZSHV_TCONF_DIR', ${SH_ZERO_DIR}/, \$PWD, VATS/)"
    exit 1
fi
# }}}
# Restart with proper binary (configuration is loaded) {{{
[ -z "$ZSH_VERSION" ] && exec /usr/bin/env "$zsh_control_bin" -f -c "source \"$0\" \"$1\" \"$2\" \"$3\" \"$4\" \"$5\" \"$6\" \"$7\" \"$8\" \"$9\""
# }}}
# INIT {{{
typeset -g ZERO="${(%):-%N}" # this gives immunity to functionargzero being unset
typeset -g ZERO_DIR="${ZERO:h}"

emulate zsh -o warncreateglobal -o extendedglob -o typesetsilent

fpath[1,0]=( ../Functions/Misc )
autoload colors; colors

typeset -g REPLY
typeset -ga reply

trap "coproc exit; return" TERM INT QUIT

typeset -g i
for i in "${ZERO_DIR}/"__error*.def; do
    source "$i"
done

# Some fallbacks (currently unused)
[[ "$test_bin" = "local-zsh" ]] && test_bin="${VATS_exe}"
[[ -z "$test_bin" ]] && test_bin="../Src/zsh"
# }}}
# Set of filters, applied in order {{{
local -A filters
filters=(
    "1-ByAt" "(#b)(#s)(==[0-9]##==[[:blank:]]##)((#B)(by|at) 0x[A-F0-9]##: )(?##)[[:blank:]]\(([^:]##:[0-9]##)\)(#e)"
    "2-ByAt" "(#b)(#s)(==[0-9]##==[[:blank:]]##)((#B)(by|at) 0x[A-F0-9]##: )(?##)[[:blank:]]\((in) ([^\)[:blank:]]##)\)(#e)"
    "3-ByAt" "(#b)(#s)(==[0-9]##==[[:blank:]]##)((#B)(by|at) 0x[A-F0-9]##: )(?##)(#e)"
    "4-TestDesc" "(#b)(#s)VATS-test-desc: (*)" # No PID, explained at "*TestDesc" if-fork
    "5-Summary" "(#b)(#s)(==[0-9]##==[[:blank:]]##)([^:]##:|Use --track*)(?#)(#e)"
    "6-Error" "(#b)(#s)(==[0-9]##==[[:blank:]]##)([^[:blank:]]?##)(#e)"
    "7-Info"  "(#b)(#s)(==[0-9]##==[[:blank:]]##)([^[:blank:]]?##)(#e)"
    "8-Blank" "(#b)(#s)(==[0-9]##==[[:blank:]]#)(#e)"
)

# Helper regexes
local reachable_pat="(#b)(#s)(==[0-9]##==[[:blank:]]##)Reachable blocks?##(#e)"
local conditional_pat="(#b)(#s)(==[0-9]##==[[:blank:]]##)Conditional jump?##(#e)"
local invalid_readwrite_pat="(#b)(#s)(==[0-9]##==[[:blank:]]##)Invalid (read|write)?##(#e)"
local address_pat="(#b)(#s)(==[0-9]##==[[:blank:]](#c2,10))Address 0x?##(#e)"
# }}}
# Theme {{{
local -A theme
theme=(
    pid                 $fg_bold[black]
    byat                $fg_no_bold[yellow]
    func                $fg_bold[blue]
    where_path          $fg_no_bold[red]
    where_file          $fg_bold[white]
    where_linenr        $fg_no_bold[magenta]
    summary_header      $fg_bold[green]
    summary_body        $fg_no_bold[green]
    summary_linenr      $fg_no_bold[magenta]
    error               $fg_bold[red]
    info                $fg_no_bold[yellow]
    number              $fg_no_bold[magenta]
    symbol              $fg_bold[black]
    skip_msg            $fg_bold[black]
    pre_test_desc       $fg_no_bold[white]
    test_desc           $fg_no_bold[yellow]
    test_desc_marks     $fg_bold[blue]
    the_test_desc_marks "@@@"
    rst                 $reset_color
)
# }}}

#
# Testers
#

# Enable global mdebug (not local as with `interested_in')
# It's almost always better to use `interested_in' way
(( ${+mdebug} )) || declare mdebug
# Assign a function name / pattern to see log messages
# only when a stacktrace and an error definition are
# containing the function
(( ${+interested_in} )) || declare interested_in=""
# FUNCTION: mdebug_mode {{{
mdebug_mode()
{
    [[ "$mdebug" = (1|yes|on) ]]
}
# }}}
# FUNCTION: is_error {{{
is_error() {
    [[ "$1" = "6-Error/"* ]]
}
# }}}
# FUNCTION: is_blank {{{
is_blank() {
    [[ "$1" = "8-Blank/"* ]]
}
# }}}
# FUNCTION: which_byat {{{
# Returns index of the type of ByAt line, inside REPLY parameter
# ByAt line: (by|at) 0xADDRESS: ...
which_byat() {
    [[ "$1" = "1-ByAt/"* ]] && { REPLY="1"; return; }
    [[ "$1" = "2-ByAt/"* ]] && { REPLY="2"; return; }
    [[ "$1" = "3-ByAt/"* ]] && { REPLY="3"; return; }
    REPLY="0"
}
# }}}
# FUNCTION: summaries_enabled {{{
summaries_enabled()
{
    [[ "$summaries" = "1" || "$summaries" = "yes" || "$summaries" = "on" ]]
}
# }}}
# FUNCTION: info_enabled {{{
info_enabled()
{
    [[ "$info" = "1" || "$info" = "yes" || "$info" = "on" ]]
}
# }}}

#
# Business logic
#

# FUNCTION: process_block {{{
#
# Every finished block is passed to this function. It decides to
# just print it, or convert to stack trace and match to error
# definitions - suppressing full block if there is a match.
#
# Input:
#   $1 - block of text (i.e. set of lines, separated by "<->",
#   occurred after Valgrind blank line i.e. ==<PID ONLY>==)
# Output:
#   stdout - Valgrind block of text printed OR suppressed
#
process_block() {
    local -a bl first_subblock_funs second_subblock_funs
    local blank="" first second test_desc="$2"

    bl=( "${(@s:<->:)1}" )
    if is_blank "${bl[1]}"; then
        blank="${bl[1]}"
        shift 1 bl
    fi

    if is_error "${bl[1]}"; then
        which_byat "${bl[2]}"
        if [[ "$REPLY" != "0" ]]; then
            first="${bl[1]}"
            shift 1 bl
            integer found_idx
            found_idx=${bl[(I)*=[[:blank:]]##Address*0x*]}

            if [[ "$found_idx" -eq "0" ]]; then
                reply=()
                to_clean_stacktrace "${bl[@]}"
                if test_stack_trace "${reply[@]}"; then
                    [[ -n "$test_desc" && "$last_tdesc" != "$test_desc" ]] && { print "${theme[pre_test_desc]}Follow report(s) for test:${theme[rst]} ${theme[test_desc_marks]}${theme[the_test_desc_marks]}${theme[rst]} ${theme[test_desc]}$test_desc${theme[rst]} ${theme[test_desc_marks]}${theme[the_test_desc_marks]}${theme[rst]}"; last_tdesc="$test_desc"; }
                    show_block "$blank" "$first" "${bl[@]}"
                else
                    [[ -n "$test_desc" && "$last_tdesc" != "$test_desc" ]] && { print "${theme[pre_test_desc]}Follow report(s) for test:${theme[rst]} ${theme[test_desc_marks]}${theme[the_test_desc_marks]}${theme[rst]} ${theme[test_desc]}$test_desc${theme[rst]} ${theme[test_desc_marks]}${theme[the_test_desc_marks]}${theme[rst]}"; last_tdesc="$test_desc"; }
                    print -r -- "${theme[skip_msg]}Skipped single-block error: $REPLY${theme[rst]}"
                fi
            else
                second="${bl[found_idx]}"
                first_subblock_funs=( ${(@)bl[1,found_idx-1]} )
                second_subblock_funs=( ${(@)bl[found_idx+1,-1]} )

                reply=()
                to_clean_stacktrace "${first_subblock_funs[@]}"
                reply+=( "--BLOCK--" )
                to_clean_stacktrace "${second_subblock_funs[@]}"

                if test_stack_trace "${reply[@]}"; then
                    [[ -n "$test_desc" && "$last_tdesc" != "$test_desc" ]] && { print "${theme[pre_test_desc]}Follow report(s) for test:${theme[rst]} ${theme[test_desc_marks]}${theme[the_test_desc_marks]}${theme[rst]} ${theme[test_desc]}$test_desc${theme[rst]} ${theme[test_desc_marks]}${theme[the_test_desc_marks]}${theme[rst]}"; last_tdesc="$test_desc"; }
                    show_block "$blank" "$first" "${first_subblock_funs[@]}" "$second" ${second_subblock_funs[@]}
                else
                    [[ -n "$test_desc" && "$last_tdesc" != "$test_desc" ]] && { print "${theme[pre_test_desc]}Follow report(s) for test:${theme[rst]} ${theme[test_desc_marks]}${theme[the_test_desc_marks]}${theme[rst]} ${theme[test_desc]}$test_desc${theme[rst]} ${theme[test_desc_marks]}${theme[the_test_desc_marks]}${theme[rst]}"; last_tdesc="$test_desc"; }
                    print -r -- "${theme[skip_msg]}Skipped double-block error: $REPLY${theme[rst]}"
                fi
            fi
            return
        fi
    fi

    show_block ${(@s:<->:)1}
}
# }}}
# FUNCTION: process_umblock {{{
# Block of unmatched lines (e.g. program output)
process_umblock() {
    print -rl -- "$@"
}
# }}}
# FUNCTION: to_clean_stacktrace {{{
#
# Input:
#   $@ - by/at lines from Valgrind output
#
# Output:
#   $reply array, appended with stack trace (ordered function names)
#
to_clean_stacktrace()
{
    local -a lines out match mbegin mend
    local l
    lines=( "$@" )

    for l in "${lines[@]}"; do
        which_byat "$l"
        if [[ "$REPLY" = 1 ]]; then
            if [[ "${l#*/}" = ${~filters[1-ByAt]} ]]; then
                out+=( $match[3] );
            fi
        elif [[ "$REPLY" = 2 ]]; then
            if [[ "${l#*/}" = ${~filters[2-ByAt]} ]]; then
                out+=( $match[3] );
            fi
        elif [[ "$REPLY" = 3 ]]; then
            if [[ "${l#*/}" = ${~filters[3-ByAt]} ]]; then
                out+=( $match[3] );
            fi
        fi
    done

    reply+=( "${out[@]}" )
}
# }}}
# FUNCTION: test_stack_trace {{{
#
# Input:
#   $@ - stack trace - array of function names
#
# Output:
#   $REPLY - (if matched) set to the error definition that matched
#   $? - false if stack trace matched to some error definition
#
test_stack_trace()
{
    local -a stacktrace cur_errors
    integer idx ssize found_in_trace=0
    local error var_name

    stacktrace=( "${(Oa)@}" )

    # Dynamic mdebug mode, for `interested_in' function
    [[ -n "$interested_in" && -n "${(M)stacktrace[@]:#${~interested_in}}" ]] && {
        found_in_trace=1
    }

    for (( idx = 0; idx <= 20; idx ++ )); do
        var_name="errors$idx"
        cur_errors=( "${(PA@)var_name}" )
        [[ -z "$cur_errors[1]" ]] && continue
        if [[ "${#cur_errors}" -gt 0 ]]; then
            for error in "${cur_errors[@]}"; do
                [[ "$found_in_trace" -eq 1 && "$error" = (*/[^/]#|[^/]#)${~interested_in}([^/]#/*|[^/]#) ]] && mdebug=1
                mdebug_mode && print "Processing error: $error"
                if compare_error "$error" "${stacktrace[@]}"; then
                    [[ "$found_in_trace" -eq 1 && "$error" = (*/[^/]#|[^/]#)${~interested_in}([^/]#/*|[^/]#) ]] && mdebug=0
                    # Error matched stack trace, result is false
                    # i.e. skip displaying the block
                    REPLY="$error"
                    return 1;
                fi
                [[ "$found_in_trace" -eq 1 && "$error" = (*/[^/]#|[^/]#)${~interested_in}([^/]#/*|[^/]#) ]] && mdebug=0
            done
        fi
    done

    # No error matched, return true
    return 0;
}
# }}}
# FUNCTION: compare_error {{{
#
# Input:
#   $1 - error definition
#   $@[2,-1] - stack trace to test
# Output:
#   $? - true if error matched the stack trace
#
compare_error()
{
    local error="$1"
    shift

    local -a stacktrace
    stacktrace=( "$@" )
    ssize=${#stacktrace}

    local -a parts
    parts=( "${(@s:/:)error}" )
    parts=( "${parts[@]//[[:blank:]]##/}" )

    integer stack_idx=1 greedy_used=0
    local part mode="exact"
    for part in "${parts[@]}"; do
        (( stack_idx > ssize )) && { stack_idx=-1; break; }
        if [[ "$part" = "*" ]]; then
            mode="skip"
            continue
        fi
        if [[ "$mode" = "skip" ]]; then
            # Outer loop used to implement greedy matching
            # working for first-after element only (i.e. if
            # current stack_idx matches, but stack_idx+1 also
            # matches, then skip current stack_idx, increment
            # and move onward to stack_idx+1)
            while (( 1 )); do
                # Inner loop iterating with `stack_idx' over `stacktrace'
                while [[ "${stacktrace[stack_idx]}" != ${~part} ]]; do
                    mdebug_mode && print "Looking for \`$part', skipping (in valgrind stack trace): \`${stacktrace[stack_idx]}'"
                    if [[ "${stacktrace[stack_idx]}" = "--BLOCK--" ]]; then
                        mdebug_mode && print "Didn't match 2-block error properly - \"--BLOCK--\" boundary was skipped, no match"
                        # Failed to match --BLOCK-- boundary that is
                        # used by 2-stage error reports (e.g. information
                        # about invalid write, then second sub-block with
                        # information on address used with the write)
                        return 1;
                    fi

                    stack_idx+=1
                    (( stack_idx > ssize )) && break
                done

                if (( stack_idx > ssize )); then
                    mdebug_mode && print "Failed to match element \`$part' (after \`*' in error definition)"
                    # Failed to match error-element after "*"
                    return 1;
                fi

                # Greedy matching! Don't sit down having a match
                # if the next stack trace element also has it!
                if (( stack_idx + 1 <= ssize )) && [[ "${stacktrace[stack_idx+1]}" = ${~part} ]]; then
                    greedy_used=1
                    mdebug_mode && print "Skipping a matching element (\`${stacktrace[stack_idx]}'), because next also matches (greedy matching)!"
                    stack_idx+=1
                    continue
                else
                    # Found, move to next stack element, continue to next error-part
                    mdebug_mode && print "Looking for \`$part', FOUND (in valgrind stack trace): \`${stacktrace[stack_idx]}' ${${(M)greedy_used:#1}:+(greedy)}, moving to next: \`${stacktrace[stack_idx+1]}'"
                    stack_idx+=1
                    mode="exact"
                    break
                fi
            done
        elif [[ "$mode" = "exact" ]]; then
            if [[ "${stacktrace[stack_idx]}" != ${~part} ]]; then
                mdebug_mode && print "Failed to match \`$part' (vs. valgrind stack trace element: \`${stacktrace[stack_idx]})'"
                # Failed to match error-element
                return 1;
            fi

            mdebug_mode && print "Matched $part (vs. valgrind stack trace: ${stacktrace[stack_idx]})"
            # Matched current error-part, move to next stack
            # trace element, continue to next part
            stack_idx+=1
            mode="exact"
        fi
    done

    if (( stack_idx == -1 )); then
        mdebug_mode && print "Valgrind stack trace finished first (too many error elements, no match)"
        # Had error-part to test but stack trace ended -> no match
        return 1;
    fi

    if (( stack_idx > ssize )); then
        mdebug_mode && print "Processed whole valgrind stack, used all error-parts - a match"
        # Processed whole stack trace and error-parts
        # have been fully used - match, return true
        return 0
    fi

    if (( stack_idx <= ssize )); then
        # Error-parts ended before reaching end of stack trace
        # -> in order to match, last part must be "*", i.e. skip
        # mode, and there cannot be "--BLOCK--" in the remaining
        # stack trace
        if [[ "$mode" = "skip" ]]; then
            if [[ "${stacktrace[(I)--BLOCK--]}" -gt "$stack_idx" ]]; then
                mdebug_mode && print "Single-block error definition vs. 2-block stack trace - no match"
                # No match, there remains --BLOCK-- element
                # in stack trace, it cannot be skipped
                return 1;
            fi
            mdebug_mode && print "Final \`*' in error definition - a match"
            # Match, return true
            return 0;
        else
            mdebug_mode && print "Stack trace was longer than error-parts, no match"
            return 1;
        fi
    fi

    # Unreachable
    return 0;
}
# }}}
# FUNCTION: show_block {{{
#
# Displays given block of text using colors (from theme).
# Obeys vtest.conf, its "summaries" and "info" variables
# (can suppress those sections).
#
# Input:
#   $@ - block of text to display, with type-prefixes like "7-Info/{text}"
#
# Output
#   stdout - lines printed with colors, if not suppresed by config
#
show_block()
{
    local line next_line MATCH
    integer MBEGIN MEND idx max

    max="${#}"
    for (( idx = 1; idx <= max; ++ idx )); do
        line="${@[idx]}"
        next_line="${@[idx+1]}"

        # The $filters contain patterns with the (#b) flag, so it
        # doesn't occur here, however ${match[...]} are being used

        # ByAt line: (by|at) 0xADDRESS: ...
        if [[ "$line" = "1-ByAt/"* ]]; then
            if [[ "${line#*/}" = ${~filters[1-ByAt]} ]]; then
                print "${theme[pid]}${match[1]}${theme[byat]}${match[2]}${theme[func]}${match[3]}${theme[symbol]} (${theme[where_file]}${match[4]/:/${theme[symbol]}:${theme[number]}}${theme[symbol]})${theme[rst]}"
            fi
        elif [[ "$line" = "2-ByAt/"* ]]; then
            if [[ "${line#*/}" = ${~filters[2-ByAt]} ]]; then
                print "${theme[pid]}${match[1]}${theme[byat]}${match[2]}${theme[func]}${match[3]}${theme[symbol]} (${theme[rst]}${match[4]} ${theme[where_path]}${match[5]}${theme[symbol]})${theme[rst]}"
            fi
        elif [[ "$line" = "3-ByAt/"* ]]; then
            if [[ "${line#*/}" = ${~filters[3-ByAt]} ]]; then
                print "${theme[pid]}${match[1]}${theme[byat]}${match[2]}${theme[func]}${match[3]}${theme[rst]}"
            fi
        elif [[ "$line" = "5-Summary/"* ]]; then
            if ! summaries_enabled; then
                continue
            fi
            if [[ "${line#*/}" = ${~filters[5-Summary]} ]]; then
                if [[ "${match[2]}" = [A-Z[:blank:]]##[:] ]]; then
                    match[3]="${match[3]//(#m) [0-9,]## /${theme[number]}$MATCH${theme[rst]}}"
                    print "${theme[pid]}${match[1]}${theme[summary_header]}${match[2]}${theme[rst]}${match[3]}"
                else
                    match[3]="${match[3]//(#m) [0-9,]## /${theme[number]}$MATCH${theme[rst]}}"
                    print "${theme[pid]}${match[1]}${theme[summary_body]}${match[2]}${theme[rst]}${match[3]}"
                fi
            fi
        elif [[ "$line" = "6-Error/"* ]]; then
            if [[ "${line#*/}" = ${~filters[6-Error]} ]]; then
                print "${theme[pid]}${match[1]}${theme[error]}${match[2]}${theme[rst]}"
            fi
        elif [[ "$line" = "7-Info/"* ]]; then
            if ! info_enabled; then
                continue
            fi
            if [[ "${line#*/}" = ${~filters[7-Info]} ]]; then
                print "${theme[pid]}${match[1]}${theme[info]}${match[2]}${theme[rst]}"
            fi
        elif [[ "$line" = "8-Blank/"* ]]; then
            if [[ "$next_line" = "5-Summary/"* ]]; then
                if ! summaries_enabled; then
                    continue
                fi
            fi
            print "${theme[pid]}${line#*/}${theme[rst]}"
        fi
    done
}
# }}}

#
# Main code
#

# Valgrind output processing {{{
coproc 2>&1 ${valgrind_path:-valgrind} "$@"

integer count=0
typeset matched pid prev_matched last_tdesc
typeset -a block umblock
typeset -A pid_to_block blank_seen test_desc

while read -p line; do
    pid="${${(@s:==:)line}[2]}"

    matched=""
    for key in ${(onk)filters[@]}; do
        pat=${filters[$key]}
        if [[ "$line" = $~pat ]]; then
            # Is it 7-Info line of Valgrind text occurring? It looks like the
            # 6-Error line, however additional constraints make it a 7-Info
            # line. See $filters association above
            if [[ $key = *Error && \
                ( $line = ${~reachable_pat} || "${blank_seen[$pid]}" -eq "0" ) && \
                    $line != ${~conditional_pat} &&
                    $line != ${~invalid_read_pat} &&
                    $line != ${~invalid_readwrite_pat} &&
                    $line != ${~address_pat}
            ]]; then
                key="7-Info"
            fi

            # Is it a blank line of Valgrind text occuring? It terminates the block
            if [[ "$key" = *Blank ]]; then
                blank_seen[$pid]=1
                process_block "${${pid_to_block[$pid]}%\<->}" "${test_desc[0]}"
                # Start a new block of Valgrind text
                pid_to_block[$pid]="${key}/${line}<->"
            # Is it an Error line of Valgrind text occuring after Summary line?
            # It terminates the block
            elif [[ "$prev_matched" = *Summary && "$key" = *Error ]]; then
                process_block "${pid_to_block[$pid]}" "${test_desc[0]}"
                # Start a new block of Valgrind text
                pid_to_block[$pid]="${key}/${line}<->"
            elif [[ "$key" = *TestDesc ]]; then
                # It was hard to embed the proper PID within ===PID=== bit -
                # - valgrind spawns many subprocesses and this is weird, as
                # ztst.zsh runs on the tested Zsh ($ZTST_exe) - so in general
                # a single instance runs all tests. However common assign key
                # (the 0) works great so it's not a priority to "fix" this
                test_desc[0]="${match[1]}"
            else
                # Build the block of Valgrind text, remembering type of each
                # line added to the block (the ${key}/-prefix)
                pid_to_block[$pid]+="${key}/${line}<->"
            fi

            # Unmatched block is terminated by a match (if we are here then we
            # have a match) - process it
            if [[ "$prev_matched" = *Unmatched ]]; then
                process_umblock $umblock
                umblock=()
            fi

            # Mark that the for loop found a type of the processed line: $key
            matched="$key"
            break
        fi
    done

    # Build also a block from unmatched (unrecognized) Valgrind text (if there
    # was no match in last for-loop run, i.e. if [[ -z $matched ]])
    if [[ -z "$matched" ]]; then
        matched="Unmatched"
        umblock+=( "$line" )
    fi

    # Remember the type of the now previous line
    prev_matched="$matched"
done
# }}}
