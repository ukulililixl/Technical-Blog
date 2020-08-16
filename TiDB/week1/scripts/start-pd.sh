#!/bin/bash

pd="172.31.80.111"
deploy_dir=/home/tidb/deploy
pd_data_dir=${deploy_dir}/pd1
pd_log=${deploy_dir}/pd1.log

ssh ${pd} "pd-server --name=pd1 --data-dir=${pd_data_dir} --client-urls=\"http://${pd}:2379\" --peer-urls=\"http://${pd}:2380\" --initial-cluster=\"pd1=http://${pd}:2380\" --log-file=${pd_log} &" &
