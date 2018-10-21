# Ring in OpenStack Swift

##### What swift does in the script "remakerings" in SAIO tutorial?

* It first change working directory to `/etc/swift`.

```bash
#!/bin/bash
set -e
cd /etc/swift
```

* Then delete all files related to ring data structure

```bash
rm -f *.builder *.ring.gz backups/*.builder backups/*.ring.gz
```

* Then it uses a script `swift-ring-builder` to initialize a ring?

```bash
swift-ring-builder object.builder create 10 3 1
```

​	What does the script `swift-ring-builder` do? It starts from `swift.cli.ringbuilder.main`

##### swift-ring-builder.main -> create

We first take a look at what does the `main` method in swift.cli.ringbuilder do.

It first parses the command line parameter and get corresponding `builder_file` and `ring_file`. For exmple, when processing the command `swift-ring-builder object.builder create 10 3 1`, corresponding `builder_file` is `object.builder` and `ring_file` is `object.ring.gz`.



Second, it load a ring builder under `swift.common.ring`. In our example, `swift.common.ring.RingBuilder(object.builder)` is loaded. It runs swift.common.ring.RingBuilder.load(object.builder) and find that file "object.builder" is not found. At this time, RingBuilder raises an error and in swift.cli.ringbuilder.main deals with this error. client finds that it is in the step of creating a ring so it ignore this error.



Third, it creates a backup directory under `/etc/swift`	.



Fourth, it calls `Commands.create`. In this function, it creates a file called "object.builder" with parameter `part_power = 10`, `replicas = 3`, `min_part_hours = 1`. 

* part_power
  * number of partitions = 2^10
* replicas
  * number of replicas for each partition is 3
* min_part_hours
  * minimum number of hours between partition changes is 1 (**???????**)

In this function, it creates a RingBuilder with these three command line parameters.  Actually, RingBuilder has several important data structures such as `_replica2part2dev`. We take a look at these data structures when we read source code in other processes.

It is also in this function, that the builder we create is serialized and persist to `/etc/swift` as well as `/etc/swift/backup`. 



Up to now, we have created an empty ring. This empty ring is an object ring. It is serialized as `/etc/swift/object.builder` and `/etc/swift/backup/1539098662.object.builder`. Note that the number `1539098662` is created randomly by `uuid` inside RingBuilder.



Next, we go back to the our initial purpose to study the script `remakering`.

`swift-ring-builder object.builder add r1z1-127.0.0.1:6010/sdb1 1`

How to understand this command?

* object.builder
  * This is the ring that we have created previously. And we want to add a new device into this ring.
* r1-z1-127.0.0.1:6010/sdb1 
  * `r1` means region 1
  * `z1` means zone 1
  * `127.0.0.1` is the ip of the new device
  * `6010` is the port that the new device listens on
  * `sdb1` is the device name
* 1
  * weight of this new device is 1

Inside `swift.cli.ringbuilder`, `RingBuilder.add_dev` is called to add a device into the ring. Each device is a dict. It maintains the following keys for a device:

* id
  * Inside swift, dev id starts from 0 and increases as the devices increases
* weight
* region
* zone
  * Usually, a partition is assigned to $replication number of devices, and the devices are not in the same (region, zone) pair if there is enough choices available
* ip
* port
* device (name)
* meta (extra field)

Similar processes happen for the following command:

```bash
swift-ring-builder object.builder add r1z2-127.0.0.2:6020/sdb2 1
swift-ring-builder object.builder add r1z3-127.0.0.3:6030/sdb3 1
swift-ring-builder object.builder add r1z4-127.0.0.4:6040/sdb4 1
```



Now let's take a look at the `rebalance` process.

`swift-ring-builder object.builder rebalance`

Code details are record in google sheet. We only take a look at the job in rebalance. Rebalance assigns partition to divices. There is an internal data structure called `_replica2part2dev`. It contains 3 arrays in our example because we have replica=3. For each array, the length is the number of partitions (1024 in our example). The value in the `_replica2part2dev[i][j]=deviceID`. In this way, devices are assigned to partitions.



After we create all the rings, the ring data structure are serialized and stored into disk.

```bash
/etc/swift/object.builder
/etc/swift/object.ring.gz
```

##### summary

We can use a simple example to illustrate the ring data structure in swift.

* We create 2^4=16 partitions. And we set replication = 3.

```bash
$> swift-ring-builder object.builder create 4 3 1
```

* Then we add devices into ring

```bash
$> swift-ring-builder object.builder add r1z1-127.0.0.1:6020/sdb1 1
$> swift-ring-builder object.builder add r1z2-127.0.0.2:6020/sdb2 1
$> swift-ring-builder object.builder add r1z3-127.0.0.3:6020/sdb3 1
$> swift-ring-builder object.builder add r1z4-127.0.0.4:6020/sdb4 1
```

The four devices are assigned `deviceID` from `0` to `3`.

* Finally we call rebalance to assign partitions to devices

```bash
$> swift-ring-builder object.builder rebalance
```

After rebalance the ring, the internal data structure `_replica2part2dev` contains 3 arrays:

| partitionID | 0    | 1    | 2    | 3    | 4    | 5    | 6    | 7    | 8    | 9    | 10   | 11   | 12   | 13   | 14   | 15   |
| ----------- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| array0      | 2    | 0    | 3    | 0    | 2    | 0    | 1    | 2    | 2    | 0    | 3    | 1    | 3    | 1    | 1    | 3    |
| array1      | 0    | 1    | 2    | 1    | 0    | 1    | 3    | 0    | 0    | 1    | 2    | 3    | 2    | 3    | 3    | 2    |
| array2      | 1    | 3    | 0    | 3    | 1    | 3    | 2    | 1    | 1    | 3    | 0    | 2    | 0    | 2    | 2    | 0    |

How is this data structure used in swift? I think it can be used in placement. When an object is assigned to a partition, swift will search for this data structure to get corresponding deviceID.

We create independent `rings` for `account` and `container ` management. For `object` management, the `ring` should be consistenct with `storage polices` configured in `/etc/swift/swift.conf`. For example, in our `/etc/swift/swift.conf`:

```bash
[storage-policy:0]
name = gold
policy_type = replication
default = yes

[storage-policy:1]
name = silver
policy_type = replication

[storage-policy:2]
name = ec42
policy_type = erasure_coding
ec_type = liberasurecode_rs_vand
ec_num_data_fragments = 4
ec_num_parity_fragments = 2

[storage-policy:3]
name = ec21
policy_type = erasure_coding
ec_type = liberasurecode_rs_vand
ec_num_data_fragments = 2
ec_num_parity_fragments = 1
```

We have 4 storage policies. As a result, when we create rings before we start Swift, we should create 4 rings in addition to account ring and container ring:

```bash
#!/bin/bash

set -e

cd /etc/swift

rm -f *.builder *.ring.gz backups/*.builder backups/*.ring.gz


swift-ring-builder object.builder create 10 3 1
swift-ring-builder object.builder add r1z1-127.0.0.1:6010/sdb1 1
swift-ring-builder object.builder add r1z2-127.0.0.2:6020/sdb2 1
swift-ring-builder object.builder add r1z3-127.0.0.3:6030/sdb3 1
swift-ring-builder object.builder add r1z4-127.0.0.4:6040/sdb4 1
swift-ring-builder object.builder rebalance

swift-ring-builder object-1.builder create 10 2 1
swift-ring-builder object-1.builder add r1z1-127.0.0.1:6010/sdb1 1
swift-ring-builder object-1.builder add r1z2-127.0.0.2:6020/sdb2 1
swift-ring-builder object-1.builder add r1z3-127.0.0.3:6030/sdb3 1
swift-ring-builder object-1.builder add r1z4-127.0.0.4:6040/sdb4 1
swift-ring-builder object-1.builder rebalance

swift-ring-builder object-2.builder create 10 6 1
swift-ring-builder object-2.builder add r1z1-127.0.0.1:6010/sdb1 1
swift-ring-builder object-2.builder add r1z1-127.0.0.1:6010/sdb5 1
swift-ring-builder object-2.builder add r1z2-127.0.0.2:6020/sdb2 1
swift-ring-builder object-2.builder add r1z2-127.0.0.2:6020/sdb6 1
swift-ring-builder object-2.builder add r1z3-127.0.0.3:6030/sdb3 1
swift-ring-builder object-2.builder add r1z3-127.0.0.3:6030/sdb7 1
swift-ring-builder object-2.builder add r1z4-127.0.0.4:6040/sdb4 1
swift-ring-builder object-2.builder add r1z4-127.0.0.4:6040/sdb8 1
swift-ring-builder object-2.builder rebalance

swift-ring-builder object-3.builder create 10 3 1
swift-ring-builder object-3.builder add r1z1-127.0.0.1:6010/sdb1 1
swift-ring-builder object-3.builder add r1z2-127.0.0.2:6020/sdb2 1
swift-ring-builder object-3.builder add r1z3-127.0.0.3:6030/sdb3 1
swift-ring-builder object-3.builder add r1z4-127.0.0.4:6040/sdb4 1
swift-ring-builder object-3.builder rebalance

swift-ring-builder container.builder create 10 3 1
swift-ring-builder container.builder add r1z1-127.0.0.1:6011/sdb1 1
swift-ring-builder container.builder add r1z2-127.0.0.2:6021/sdb2 1
swift-ring-builder container.builder add r1z3-127.0.0.3:6031/sdb3 1
swift-ring-builder container.builder add r1z4-127.0.0.4:6041/sdb4 1
swift-ring-builder container.builder rebalance

swift-ring-builder account.builder create 10 3 1
swift-ring-builder account.builder add r1z1-127.0.0.1:6012/sdb1 1
swift-ring-builder account.builder add r1z2-127.0.0.2:6022/sdb2 1
swift-ring-builder account.builder add r1z3-127.0.0.3:6032/sdb3 1
swift-ring-builder account.builder add r1z4-127.0.0.4:6042/sdb4 1
swift-ring-builder account.builder rebalance
```

