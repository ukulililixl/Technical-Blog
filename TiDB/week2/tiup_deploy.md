# Deploy TiDB via TiUP

### My Nodes
All the 5 nodes are of the type `ecs.g6e.large`:
* vCPU: 2
* Memory: 8 GiB
*

### Install TiUP

```bash
$> curl --proto '=https' --tlsv1.2 -sSf https://tiup-mirrors.pingcap.com/install.sh | sh
$> tiup cluster
$> tiup update --self && tiup update cluster
$> tiup --binary cluster
/home/tidb/.tiup/components/cluster/v1.0.9/tiup-cluster
```

Topology.yaml:
```yaml
global:
user: "tidb"
ssh_port: 22
deploy_dir: "/tidb-deploy"
data_dir: "/tidb-data"

pd_servers:
- host: 172.31.80.111

tidb_servers:
- host: 172.31.80.110

tikv_servers:
- host: 172.31.80.112
- host: 172.31.80.113
- host: 172.31.80.114

monitoring_servers:
- host: 172.31.80.110

grafana_servers:
- host: 172.31.80.110

alertmanager_servers:
- host: 172.31.80.110
```

deploy:
```bash
$> tiup cluster deploy tidb-test v4.0.0 ./topology.yaml --user root -p -i /root/.ssh/id_rsa
$> tiup cluster list
$> tiup cluster display tidb-test
$> tiup cluster start tidb-test
$> tiup cluster display tidb-test
Starting component `cluster`: /home/tidb/.tiup/components/cluster/v1.0.9/tiup-cluster display tidb-test
tidb Cluster: tidb-test
tidb Version: v4.0.0
ID                   Role          Host           Ports        OS/Arch       Status   Data Dir                      Deploy Dir
--                   ----          ----           -----        -------       ------   --------                      ----------
172.31.80.110:9093   alertmanager  172.31.80.110  9093/9094    linux/x86_64  Up       /tidb-data/alertmanager-9093  /tidb-deploy/alertmanager-9093
172.31.80.110:3000   grafana       172.31.80.110  3000         linux/x86_64  Up       -                             /tidb-deploy/grafana-3000
172.31.80.111:2379   pd            172.31.80.111  2379/2380    linux/x86_64  Up|L|UI  /tidb-data/pd-2379            /tidb-deploy/pd-2379
172.31.80.110:9090   prometheus    172.31.80.110  9090         linux/x86_64  Up       /tidb-data/prometheus-9090    /tidb-deploy/prometheus-9090
172.31.80.110:4000   tidb          172.31.80.110  4000/10080   linux/x86_64  Up       -                             /tidb-deploy/tidb-4000
172.31.80.112:20160  tikv          172.31.80.112  20160/20180  linux/x86_64  Up       /tidb-data/tikv-20160         /tidb-deploy/tikv-20160
172.31.80.113:20160  tikv          172.31.80.113  20160/20180  linux/x86_64  Up       /tidb-data/tikv-20160         /tidb-deploy/tikv-20160
172.31.80.114:20160  tikv          172.31.80.114  20160/20180  linux/x86_64  Up       /tidb-data/tikv-20160         /tidb-deploy/tikv-20160
```

### Dashboard configuration

We need to configure the network settings for VMs in aliyun, for the purpose to enable the access to the port 2379. I just enable the access for all the ports from all source ips. After the configuration, I can access the dashboard from the public ip of pd.
