#!/bin/bash

tidb=172.31.80.110
log_file=/home/tidb/deploy/tidb1.log
pd=172.31.80.111

ssh $tidb "tidb-server --store=tikv --path=\"${pd}:2379\" --log-file=${log_file} &" &
