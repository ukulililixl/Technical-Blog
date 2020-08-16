# Install TiDB from Source Code

No official link provided in the home page of [document](https://docs.pingcap.com/tidb/stable). I need to find some text in the source code package about how to build the source code.
### Pre-requisite
* Machines
  - I apply for 5 machines in Aliyun - Hong Kong.
  - 1 tidb
    - 172.31.80.110
  - 1 pd
    - 172.31.80.111
  - 3 tikvs
    - 172.31.80.112
    - 172.31.80.113
    - 172.31.80.114
  - Configure ssh without passwd
    ```bash
    $> vim /etc/ssh/sshd_config
    PasswordAuthentication yes
    $> passwd
    $> service ssh restart
    ```
  - Configure new user `tidb`
    ```bash
    $> adduser tidb
    $> visudo
    tidb    ALL=(ALL:ALL) ALL
    tidb    ALL=(ALL) NOPASSWD: ALL
    ```
  - Configure hosts
    ```bash
    $> vim /etc/hostname
    $> vim /etc/hosts
        172.31.80.110   tidb
        172.31.80.111   pd
        172.31.80.112   tikv1
        172.31.80.113   tikv2
        172.31.80.114   tikv3
    $> reboot
    ```
  - Configure ssh without passwd
    - log in as user `tidb`
    ```bash
    $> ssh-keygen
    $> ssh-copy-id tidb
    $> ssh-copy-id pd
    $> ssh-copy-id tikv1
    $> ssh-copy-id tikv2
    $> ssh-copy-id tikv3
    ```
  - comment the following lines in `~/.bashrc`
    ```bash
    # If not running interactively, don't do anything
    case $- in
        *i*) ;;
          *) return;;
    esac
    ```
  - configure max open files
  ```bash
  $> tail /etc/security/limits.conf
    * soft nofile 102400
    * hard nofile 102400
  $> reboot
  ```

### Compile source code
I compile all the source code in node `tidb`
* Install git
  ```bash
  $> sudo apt-get install git
  ```
* Install Go 1.13
  ```bash
  $> sudo apt remove 'golang-*'
  $> wget https://dl.google.com/go/go1.13.9.linux-amd64.tar.gz
  $> tar xf go1.13.9.linux-amd64.tar.gz
  $> sudo mv go /usr/local/go-1.13
  $> vim .bashrc
  # GO
  export GOROOT=/usr/local/go-1.13
  export PATH=$GOROOT/bin:$PATH
  $> source .bashrc
  $> which go
  ```
* Other tools
  ```bash
  $> sudo apt-get install zip
  ```

##### Build TiDB
Make sure the machine to build TiDB has Go installed.
```bash
$> git clone https://github.com/pingcap/tidb.git
$> make
```
##### Build PD
Make sure the machine to build PD has Go installed.
```bash
$> git clone https://github.com/pingcap/pd.git
$> cd pd
$> make
```
##### Build TiKV
* Install rustup
  ```bash
  $> curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  $> source ~/.cargo/env
  $>
  ```
* Install cmake
  ```bash
  $> sudo apt-get install cmake
  ```
* Build (It takes several minutes to build TiKV)
  ```bash
  $> git clone https://github.com/tikv/tikv.git
  $> cd tikv
  $> rustup component add rustfmt
  $> rustup component add clippy
  $> make build
  $> cargo check --all
  $> cargo install cargo-watch
  $> cargo watch -s "cargo check --all"
  $> make dev
  ```
  `make dev` fails as the following tests fail
  ```bash
  Running target/debug/deps/failpoints-a15774584eb648bb
  ```
### Deploy
* Generate deploy folder in node `tidb`
  ```bash
  $> mkdir -p ~/deploy
  $> mkdir -p ~/deploy/bin
  $> cd ~/deploy
  $> cat sync.sh
  # cp binaries
  tidb_home=/home/tidb/tidb
  cp ${tidb_home}/bin/* ./bin

  pd_home=/home/tidb/pd
  cp ${pd_home}/bin/* ./bin

  tikv_home=/home/tidb/tikv
  cp ${tikv_home}/target/debug/tikv-server ./bin

  for node in pd tikv1 tikv2 tikv3
  do
    ssh $node "mkdir -p ~/deploy"
    ssh $node "mkdir -p ~/deploy/bin"
    scp ./bin/* $node:~/deploy/bin
  done

  $> ./sync.sh
  ```
* Edit `~/.bashrc` in each node
  ```bash
  $> tail ~/.bashrc
  # TiDB
  export TiDB_Deploy=/home/tidb/deploy
  export PATH=${TiDB_Deploy}/bin:$PATH
  $> source ~/.bashrc
  ```
* start pd
  ```bash
  $> cat bin/start-pd.sh
  #!/bin/bash
  pd=172.31.80.111
  deploy_dir=/home/tidb/deploy
  pd_data_dir=${deploy_dir}/pd1
  pd_log=${deploy_dir}/pd1.log
  ssh $pd "./bin/pd-server \
  --name=pd1 --data-dir=${pd_data_dir} \
  --client-urls=\"http://${pd}:2379\" \
  --peer-urls=\"http://${pd}:2380\" \
  --initial-cluster=\"pd1=http://${pd}:2380\" \
  --log-file=${pd_log} &"
  ```
* start 3 tikv
  ```bash
  $> cat bin/start-tikv.sh
  #!/bin/bash

  pd=172.31.80.111
  tikv1=172.31.80.112
  tikv2=172.31.80.113
  tikv3=172.31.80.114

  data_dir=/home/tidb/deploy/tikv
  log_file=/home/tidb/deploy/tikv.log

  for node in $tikv1 $tikv2 $tikv3
  do
    ssh $node "tikv-server \
    --pd-endpoints=\"${pd}:2379\" \
    --addr=\"${node}:20160\" \
    --data-dir=${data_dir} \
    --log-file=${log_file} &" &
  done

  $> start-tikv.sh
  ```
* verify
  ```bash
  $> pd-ctl store -u http://172.31.80.111:2379
  ```
  Official document provides "-d" as a parameter, which does not work.
* start tidb
  ```bash
  #!/bin/bash

  tidb=172.31.80.110
  log_file=/home/tidb/deploy/tidb1.log
  pd=172.31.80.111

  ssh $tidb "tidb-server \
  --store=tikv --path=\"${pd}:2379\" \
  --log-file=${log_file} &" &
  ```
