#!/bin/bash

failed=0

printf "Add verible to path\n"

export PATH=$(pwd)/verible/bin/:$PATH 

core_names=($(fusesoc --cores-root . list-cores | awk 'NR>5{print$1}'))

core_names=${core_names//$'\n'/' '}

for i in "${core_names[@]}"; do
    if $(fusesoc --cores-root . run --target lint "$i"); then 
      echo "Lint passed for $i"
    else 
      echo "Lint failed for $i"
      failed=1
    fi
done

exit $failed
