# GRC (Generic Colorizer) aliases, csh form.
#
# TRACKS envs/bash/global/grc/etc/profile.d/grc.sh, which is vendored upstream
# sh syntax (it ends in a bare `return 0`) and therefore cannot be sourced by
# csh. This file reproduces the same alias set natively.
#
# Sourced from global/tcshrc BEFORE global/aliases.csh, exactly as the bash env
# sources grc.sh before aliases.sh -- so the loadout's own `df`, `du`, `ps` and
# friends override the grc versions in both shells, not just one.
#
# `env` is deliberately absent: it is commented out upstream too (colorizing env
# breaks `env VAR=x cmd`, which several loadout aliases rely on).
#
# NOTE the guard shape. Upstream bails with `return 0`; the obvious csh
# translation is `exit`, and that is WRONG -- in csh, `exit` from a SOURCED file
# exits the SHELL, not the source. The guards are therefore one nested `if`,
# never an early exit. Same rule as the rc files themselves.

set _loadout_grc_ok = 0
if ( $?GRC_ALIASES ) then
    if ( "$GRC_ALIASES" == "true" && -X grc && $?TERM ) then
        if ( "$TERM" != "dumb" ) then
            if ( { tty -s } ) set _loadout_grc_ok = 1
        endif
    endif
endif

if ( $_loadout_grc_ok == 1 ) then
    alias colourify 'grc -es'

    foreach _loadout_grc ( blkid df diff docker docker-compose docker-machine du \
                           free fdisk findmnt make gcc g++ id ip iptables as gas \
                           journalctl kubectl ld lsof lsblk lspci netstat ping ss \
                           traceroute traceroute6 head tail dig mount ps mtr \
                           semanage getsebool ifconfig sockstat )
        if ( -X $_loadout_grc ) alias $_loadout_grc "grc -es $_loadout_grc"
    end
    unset _loadout_grc

    # ./configure is not a PATH command, so it gets no -X guard.
    alias configure 'grc -es ./configure'
endif

unset _loadout_grc_ok
