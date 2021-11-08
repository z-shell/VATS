#!/bin/sh
# -*- Mode: sh; sh-indentation: 2; indent-tabs-mode: nil; sh-basic-offset: 2; -*-
# vim:ft=zsh:sw=2:sts=2:et

#
# /bin/sh stage, load configuration to obtain $zsh_bin
#

SH_ZERO_DIR=${0%/vruntests.zsh}

[ -z "$ZSHV_TCONF_FILE" ] && ZSHV_TCONF_FILE="vtest.conf"
[ "$1" != "${1#conf:}" ] && { ZSHV_TCONF_FILE="${1#conf:}"; shift; }

#
# Source both under sh and zsh - the former for the $zsh_control_bin
#

if [ -n "$ZSHV_TCONF_DIR" ]; then
  . "${ZSHV_TCONF_DIR}/${ZSHV_TCONF_FILE}"
elif [ -f "${SH_ZERO_DIR}/${ZSHV_TCONF_FILE}" ]; then
  . "${SH_ZERO_DIR}/${ZSHV_TCONF_FILE}"
elif [ -f "${PWD}/${ZSHV_TCONF_FILE}" ]; then
  . "${PWD}/${ZSHV_TCONF_FILE}"
elif [ -f "VATS/${ZSHV_TCONF_FILE}" ]; then
  . "VATS/${ZSHV_TCONF_FILE}"
fi

[ -z "$zsh_control_bin" ] && zsh_control_bin="zsh"

#
# Restart with zsh as interpreter
#

[ -z "$ZSH_VERSION" ] && exec /usr/bin/env "$zsh_control_bin" -f -c "source \"$0\" \"$1\" \"$2\" \"$3\" \"$4\" \"$5\" \"$6\" \"$7\" \"$8\" \"$9\""

#
# Init
#

typeset -g ZERO="${(%):-%N}" # this gives immunity to functionargzero being unset
typeset -g ZERO_DIR="${ZERO:h}"

emulate zsh -o warncreateglobal -o typesetsilent

fpath[1,0]=( ../Functions/Misc )
autoload colors; colors

test_type_msg()
{
  print "$fg[green]@@@$reset_color Test type: $fg[yellow]$1$reset_color $fg[green]@@@$reset_color Test binary: $test_bin $fg[green]@@@$reset_color Control binary: $zsh_control_bin $ZSH_VERSION $fg[green]@@@$reset_color"
}

export ZTST_exe
local cmd="${valgrind_path:-valgrind}"
local -a valargs
[[ "$main_operation_parsing" = (1|yes|on) && -x "${ZERO_DIR}/zsh-valgrind-parse.cmd" ]] && cmd="${ZERO_DIR}/zsh-valgrind-parse.cmd"
[[ "$test_bin" = "local-zsh" ]] && test_bin="${ZTST_exe}"
[[ ! -f "$test_bin" ]] && { print "VATS: Test binary ($test_bin) doesn't exist, aborting"; exit 1; }

if [[ "$test_kind" = nopossiblylost* ]]; then
  valargs=( "--leak-check=full" "--show-possibly-lost=no" )
  test_type_msg "leaks, nopossiblylost"
elif [[ "$test_kind" = error* ]]; then
  valargs=()
  test_type_msg "only errors (no leaks)"
elif [[ "$test_kind" = leak* || "$test_kind" = "full" ]]; then
  valargs=( "--leak-check=full" )
  test_type_msg "full leak check"
else
  print "VATS: Unknown test type \`$test_kind\', supported are: error, leak, nopossiblylost. Aborting."
  exit 1
fi

[[ "$track_origins" = (1|yes|on) ]] && valargs+=( "--track-origins=yes" )

[[ "$test_desc" = (1|yes|on) ]] && export VLGRND_TEST_DESC=1

local ctarg    # current arg
local line     # Decomposition trick var
local -a targs # evaluated test_bin args, non-evaluated Valgrind args
integer success failure skipped count=0

for file in "${(f)ZTST_testlist}"; do
  # Prepare test_bin-args - from the config file
  targs=()
  for ctarg in "${(z@)test_bin_args}"; do
    eval "print -rl -- $ctarg | while read line; do targs+=( \"\${(Q)line}\" ); done"
  done

  (( ++ count ))

  print "@@@@@ Starting test \`${file#./}' @@@@@"

  # Invoke Valgrind (through zsh-valgrind-parse.cmd)
  # cmd will be: zsh-valgrind-parse.cmd or valgrind,
  # depending on the option `main_operation_parsing'
  $cmd "${valargs[@]}" "$test_bin" "${targs[@]}"
done

print "**************************************"
print "$count test file(s) were ran"
print "**************************************"

return 0
