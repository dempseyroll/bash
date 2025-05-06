#!/bin/bash

for ((i=0; i<=21; i++))
    do
    curl -vvv https://www.domain.com/stuff/$i
    done
