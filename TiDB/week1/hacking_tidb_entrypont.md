# Hacking TiDB: Where is the entrypoint of TiDB transaction?

I want to run a simple transaction, and study the log
of TiDB, for the purpose to find some useful information

### Pre-requisite
* Install mysql
  ```bash
  $> sudo apt-get install mysql-client
  ```
* Log in to the database
  ```bash
  $> mysql -h 172.31.80.110 -P 4000 -u root
  ```
  After log in, we can see the following logs:
  ```text
  [server.go:388] ["new connection"] [conn=3] [remoteAddr=172.31.80.110:47870]
  ```
* create table
  ```mysql
  > use test;
  > create table mytable (id int not null primary key);
  ```
  We then see the following logs. For now, I'm not sure whether these lines all belong to the previous execution.
  ```text
  [session.go:2257] ["CRUCIAL OPERATION"] [conn=3] [schemaVersion=23] [cur_db=test] [sql="create table mytable (id int not null primary key)"] [user=root@172.31.80.110]

  [session.go:1502] ["NewTxn() inside a transaction auto commit"] [conn=3] [schemaVersion=23] [txnStartTS=418793760111722497]

  [ddl_worker.go:260] ["[ddl] add DDL jobs"] ["batch count"=1] [jobs="ID:48, Type:create table, State:none, SchemaState:none, SchemaID:1, TableID:47, RowCount:0, ArgLen:1, start time: 2020-08-16 17:56:47.009 +0800 CST, Err:<nil>, ErrCount:0, SnapshotVersion:0; "]

  [ddl.go:475] ["[ddl] start DDL job"] [job="ID:48, Type:create table, State:none, SchemaState:none, SchemaID:1, TableID:47, RowCount:0, ArgLen:1, start time: 2020-08-16 17:56:47.009 +0800 CST, Err:<nil>, ErrCount:0, SnapshotVersion:0"] [query="create table mytable (id int not null primary key)"]

  [ddl_worker.go:589] ["[ddl] run DDL job"] [worker="worker 1, tp general"] [job="ID:48, Type:create table, State:none, SchemaState:none, SchemaID:1, TableID:47, RowCount:0, ArgLen:0, start time: 2020-08-16 17:56:47.009 +0800 CST, Err:<nil>, ErrCount:0, SnapshotVersion:0"]

  ```

### Run a simple transaction

```mysql
begin;
insert into mytable values (1);
insert into mytable values (2);  
insert into mytable values (3);
commit;
```

* After running `begin`
  ```text
  [session.go:1502] ["NewTxn() inside a transaction auto commit"] [conn=4] [schemaVersion=24] [txnStartTS=418793878522167297]

  ```

* After running `insert into mytable values (1);`
  ```text
  [2pc.go:629] ["send TxnHeartBeat"] [startTS=418794028822429697] [newTTL=101800]

  [2pc.go:629] ["send TxnHeartBeat"] [startTS=418794028822429697] [newTTL=111800]

  ```
* After running `insert into mytable values (2);`, there are more lines of TxnHeartBeat.
* After running `commit;`
  ```text
  [gc_worker.go:267] ["[gc worker] starts the whole job"] [uuid=5cfda7354fc0009] [safePoint=418793935394308096] [concurrency=3]

  [gc_worker.go:1118] ["[gc worker] start resolve locks with physical scan locks"] [uuid=5cfda7354fc0009] [safePoint=418793935394308096]

  [gc_worker.go:1198] ["[gc worker] registering lock observers to tikv"] [uuid=5cfda7354fc0009] [safePoint=418793935394308096]

  [gc_worker.go:1228] ["[gc worker] checking lock observers"] [uuid=5cfda7354fc0009] [safePoint=418793935394308096]

  [gc_worker.go:1189] ["[gc worker] finish resolve locks with physical scan locks"] [uuid=5cfda7354fc0009] [safePoint=418793935394308096] [takes=4.2922ms]

  [gc_worker.go:1297] ["[gc worker] removing lock observers"] [uuid=5cfda7354fc0009] [safePoint=418793935394308096]

  [gc_worker.go:238] ["[gc worker] there's already a gc job running, skipped"] ["leaderTick on"=5cfda7354fc0009]

  [gc_worker.go:630] ["[gc worker] start delete ranges"] [uuid=5cfda7354fc0009] [ranges=0]

  [gc_worker.go:659] ["[gc worker] finish delete ranges"] [uuid=5cfda7354fc0009] ["num of ranges"=0] ["cost time"=420ns]

  [gc_worker.go:682] ["[gc worker] start redo-delete ranges"] [uuid=5cfda7354fc0009] ["num of ranges"=0]

  [gc_worker.go:711] ["[gc worker] finish redo-delete ranges"] [uuid=5cfda7354fc0009] ["num of ranges"=0] ["cost time"=357ns]

  [gc_worker.go:1476] ["[gc worker] sent safe point to PD"] [uuid=5cfda7354fc0009] ["safe point"=418793935394308096]
  ```

  * I guess `gc` means garbage collector, which might be a background routine. I think it has nothing to do with my transaction.

Up to now, I think the entrypoint might be in `session.go`.

### Learn the documents

I find that there is an official document that introduces the life of a transaction: [link](https://pingcap.com/blog-cn/tidb-source-code-reading-3/), which answers some of my questions.

* conn.go
  - Run()
    - It listening to the client requests
    - Then calls dispatch() to deal with the request.
  - dispatch()
    - There are different types of requests.
    - Each type of request is related to `handle*()`
    - To deal with sql request, it calls `handleQuery()`
  - handleQuery()
    - It seems that the current version is different with the code in the document, as I do not find `Execute` in this function.
    - It first parses the sql statement by `stmts, err := cc.ctx.Parse(ctx, sql)`
    - Then get an execution plan by `pointPlans, err = cc.prefetchPointPlanKeys(ctx, stmts)`
    - Then goes to `handleStmt`

      `err = cc.handleStmt(ctx, stmt, parserWarns, i == len(stmts)-1)`
  - handleStmt()
    - It executes the statement

      `rs, err := cc.ctx.ExecuteStmt(ctx, stmt)`
    - I grep this function and find it is in `driver_tidb.go`

Now we go to `./server/driver_tidb.go`
* server/driver_tidb.go

  `rs, err := tc.Session.ExecuteStmt(ctx, stmt)`
  * It then goes to `session.go`
* session.go
  - ExecuteStmt()
    - compiler.Compile()
      - returns  ExecStmt
  - RunStmt()
    - adapter.ExecStmt.Exec()
      - It builds executor from the plan.
      - There is a timestamp called `txnStartTS`, which I think might marks the start of a transaction.
      - However, I find that it does not initialized here as it is invalid.
    - Go back to session.go and find Txn

      `txn, err := sctx.Txn(false)`
    - Txn()
      - It seems that this function returns `TxnState`
- tidb.go
  - finishStmt()
  - autoCommitAfterStmt()
- session.go
  - CommitTxn()
  - doCommitWithRetry()
    - From the time measurement in this method, I find that the start time of Txn is at `s.sessionVars.TxnCtx.CreateTime`. So I just need to find where it is initialized. Then it is the entrypoint.
    - I find it is initialized in `PrepareTxnCtx`

### Print Hello

I add the line in `session.go`, the funciton `PrepareTxnCtx`:
```go
2168 func (s *session) PrepareTxnCtx(ctx context.Context) {
2169         if s.txn.validOrPending() {
2170                 return
2171         }
2172
2173         is := domain.GetDomain(s).InfoSchema()
2174         logutil.Logger(ctx).Info("XL debug:PrepareTxnCtx. Hello transaction!")
2175         s.sessionVars.TxnCtx = &variable.TransactionContext{
2176                 InfoSchema:    is,
2177                 SchemaVersion: is.SchemaMetaVersion(),
2178                 CreateTime:    time.Now(),
2179                 ShardStep:     int(s.sessionVars.ShardAllocateStep),
2180         }
2181         if !s.sessionVars.IsAutocommit() || s.sessionVars.RetryInfo.Retrying {
2182                 pessTxnConf := config.GetGlobalConfig().PessimisticTxn
2183                 if pessTxnConf.Enable {
2184                         if s.sessionVars.TxnMode == ast.Pessimistic {
2185                                 s.sessionVars.TxnCtx.IsPessimistic = true
2186                         }
2187                 }
2188         }
2189 }
```

However, I don't understand why tidb keeps printing this line. Are there background transactions?
