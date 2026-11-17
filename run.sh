#!/bin/zsh
# Запуск через Terminal.app (має дозвіл на Bluetooth): ./run.sh <name> <cmd...>
cd "$(dirname "$0")"
name=$1; shift
"$@" > "logs/$name.log" 2>&1
echo "exit $?" >> "logs/$name.log"
