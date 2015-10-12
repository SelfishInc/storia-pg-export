"use strict";

require("supererror")
require("long-stack-traces")

const Riak = require("basho-riak-client")
const _ = require("lodash")
const util = require("util")
const inspect = x => util.inspect(x, {colors: true, depth: 2})
const Stream = require("stream")
const parallelTransform = require("parallel-transform")
const pg = require("pg")//.native
//const Progress = require("progress")
const Progress = require("./progressbar")

const config = {
  riak: {
    pre:  _.range(0, 4).map(n => `riak0${n}.preprod.selfishbeta.com`),
    prod:
      ["172.16.2.4", "172.16.2.5", "172.16.2.252", "172.16.2.253", "172.16.2.254", "172.16.2.19"],
    minConnections: 10,
    maxConnections: 40
  },
  pg: {
    host: "10.0.0.2",
    user: "storia",
    database: "storia",
    poolSize: 50
  }
}

const environment = "prod"
const bucketType = "prod"
const schema = "buckets"

config.riak.maxParallel =
  Math.floor(config.riak[environment].length * config.riak.maxConnections * 0.8)

pg.defaults.poolSize = config.pg.poolSize

console.log("maxParallel:", config.riak.maxParallel)

var nodeTemplate = new Riak.Node.Builder()
      .withMinConnections(config.riak.minConnections)
      .withMaxConnections(config.riak.maxConnections)

const riakCluster = new Riak.Cluster({nodes: Riak.Node.buildNodes(config.riak[environment], nodeTemplate)})
const riakClient = new Riak.Client(riakCluster)

var query = require('pg-query')
query.connectionParameters = `postgres://${config.pg.user}@${config.pg.host}/${config.pg.database}`

class ResultStream extends Stream.Readable {
  constructor(riakMethod, transform) {
    super({objectMode: true})
    var i = 0
    return (...args) => {
      riakMethod.apply(null, args.concat([
        (error, values) => {
          if (!!error) {
            console.error(error)
            this.emit("error")
          }
          else {
            transform(values).forEach(v => this.push(v))
            if (values.done) this.push(null)}}]))
      return this
    }
  }

  _read() {}
}

const listKeys = bucket => new ResultStream(
  riakClient.listKeys.bind(riakClient),
  (({bucketType, bucket, keys}) => keys.map(key => ({bucketType, bucket, key}))))({bucketType, bucket})

const riakPromise = (method, transform) =>
        (...args) =>
        new Promise((resolve, reject) => {
          method.apply(this, args.concat([(err, result) => {
            if (!!err) reject(err)
            else resolve((typeof transform === 'function') ? transform(result) : result)
          }]))
        })

const fetchValue = riakPromise(riakClient.fetchValue.bind(riakClient), res => _.filter(res.values, x => !x.isTombstone)[0])
const storeValue = riakPromise(riakClient.storeValue.bind(riakClient))
const deleteValue = riakPromise(riakClient.deleteValue.bind(riakClient))

const fetch = () => parallelTransform(
  config.riak.maxParallel,
  {objectMode: true},
  function({bucket, key}, done) {
    fetchValue({bucketType, bucket, key})
      .then(
        obj => done(null, {key, value: obj.value.toString()}),
        err => { console.error(`\nerror while fetching ${bucket}/${key}\n`, err.stack);
                 done(err, null)})})

const del = () => parallelTransform(
  config.riak.maxParallel,
  {objectMode: true},
  function({bucket, key}, done) {
    deleteValue({bucketType, bucket, key})
      .then(obj => done(null, obj),
            err => { console.error(`error while deleting ${bucket}/${key}`, err.stack);
                     done(err, null)})})

const store = (tableName, valueType) => parallelTransform(
  config.pg.poolSize,
  {objectMode: true},
  function({key, value}, cb) {
    if (value === void 0) {
      console.log('\nno value received\n')
      cb(null, void 0)
    }
    else {
      query(`INSERT INTO ${tableName} (key, value) VALUES ($1, $2::${valueType});`,
            [key, value], cb)}
  })

const countKeys = bucket => {
  const query = {
    inputs: [bucketType, bucket],
    query: [{reduce: {language: "erlang",
                      module: "riak_kv_mapreduce",
                      function: "reduce_count_inputs",
                      arg: { reduce_phase_batch_size: 1000 }}}]}

  console.log(`counting keys in bucket ${bucket}...`)
  return new Promise((resolve, reject) => {
    var acc = []

    function receiveResult(error, data) {
      if (!!error) {
        console.error(error.stack)
        reject(error)
      } else {
        acc.push(data)
        if (data.done) resolve(_(acc).find(_ => _.phase === 0).response[0])
      }
    }

    riakClient.execute(new Riak.Commands.MR.MapReduce(JSON.stringify(query), receiveResult))})
}

const withProgress = (caption, total) => stream => {
  const progress = new Progress(total, {barWidth: 50, caption})
  stream.on("data", data => progress.tick())
  return stream
}

const streamPromise = stream => new Promise(
  (resolve, reject) =>
    stream
    .on("end", _ => {
      console.log("stream ended")
      resolve()
    })
    .on("error", err => reject(err))
)

const exportBucket = (bucket, table, keyType = "CHAR(16)", valueType = 'JSONB') => {
  console.log("dropping table", table)
  return query(`DROP TABLE IF EXISTS ${schema}.${table};`)
    .then( ok => {
      console.log("creating table", table)
      return query(`CREATE TABLE ${schema}.${table} (key ${keyType} PRIMARY KEY, value ${valueType});`)
    })
    .then(ok => countKeys(bucket))
    .then(count => {
      console.log(`keys in ${bucket}: ${count}`)
      return streamPromise(listKeys(bucket)
                           .pipe(fetch())
                           .pipe(withProgress(`${bucket}:`, count)(store(`${schema}.${table}`, valueType))))
    })
}

const allDone = () => {
  console.log("all done.")
  process.exit(0)
}

;([
  ["StashFile", "stashfiles", "CHAR(16)"],
  ["AltStashFile", "altstashfiles", "CHAR(33)"],
  ["Moment", "moments", "CHAR(33)"],
  ["Story", "stories", "CHAR(16)"],
  ["ACLUser", "aclusers", "CHAR(16)"],
  ["Credentials", "credentials", "VARCHAR(128)"],
  ["User", "users", "CHAR(16)"],
  // ["Comment", "comments", "CHAR(33)"],
  // ["CoreRelation-FollowsUser", "follows", "CHAR(33)", "TIMESTAMPTZ"],
  // ["CoreRelation-FollowsStory", "subscribed", "CHAR(33)", "TIMESTAMPTZ"]
  // ["Like", "Like", "CHAR(33)", "JSONB"]
]
  .map(([bucket, table, keyType, valueType]) => () => exportBucket(bucket, table, keyType, valueType)))
        .reduceRight((prev, next) => () => next().then(prev), allDone)()
        .catch(err => console.log(err.stack))

// riakClient.secondaryIndexQuery(
//     {bucketType, bucket: "Moment", indexName: "repostof_bin", indexKey: "08c31f4df706f000"},
//     (error, value) => {
//         if (!!error) console.error(error)
//         else console.log(inspect(value))
//     }
// )
