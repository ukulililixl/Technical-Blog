#!/bin/bash

pd=172.31.80.111

ssh ${pd} "sudo killall pd-server"
