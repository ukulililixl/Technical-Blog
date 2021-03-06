#!/bin/bash

pd=172.31.80.111
tikv1=172.31.80.112
tikv2=172.31.80.113
tikv3=172.31.80.114

data_dir=/home/tidb/deploy/tikv
log_file=/home/tidb/deploy/tikv.log

for node in $tikv1 $tikv2 $tikv3
do
ssh $node "tikv-server --pd-endpoints=\"${pd}:2379\" --addr=\"${node}:20160\" --data-dir=${data_dir} --log-file=${log_file} &" &
done
