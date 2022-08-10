#!/bin/bash

function set_boolean()
{
    declare -n foo=$1
    case ${2^^} in
        TRUE | T | YES | Y | 1)
            foo=true
            ;;
        FALSE | F | NO | N | 0)
            foo=false
            ;;
        *)
            if [[ "$2" == "" ]]; then
                # just flip the meaning
                foo=$(($foo ^ true))
            else
                echo "ERROR: unknown value \"$VALUE\""
                usage
                exit 1
            fi
            ;;
    esac
}
