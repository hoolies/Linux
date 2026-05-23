#!/bin/env bash

echo ''
echo $PATH | tr ':' '\n' | xargs -I {} sh -c 'if [ -d "{}" ]; then printf "\033[32m%s\033[0m\n" "{}"; else printf "\033[31m%s\033[0m\n" "{}"; fi'
