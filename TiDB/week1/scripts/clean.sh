#!/bin/bash 

pd=172.31.80.111
tikv1=172.31.80.112
tikv2=172.31.80.113
tikv3=172.31.80.114

ssh $pd "rm -rf /home/tidb/deploy/pd*"
for node in $tikv1 $tikv2 $tikv3
do
ssh $node "rm -rf /home/tidb/deploy/tikv*"
done
