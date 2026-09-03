const replicaSet = process.env.MONGO_REPLICA_SET || 'rs0'
const replicaHost = process.env.MONGO_REPLICA_HOST || 'mongo:27017'
const credentials = {
  'catalog-runtime': process.env.MONGO_CATALOG_RUNTIME_PASSWORD,
  'catalog-migration': process.env.MONGO_CATALOG_MIGRATION_PASSWORD,
  'inventory-runtime': process.env.MONGO_INVENTORY_RUNTIME_PASSWORD,
  'inventory-migration': process.env.MONGO_INVENTORY_MIGRATION_PASSWORD,
}

for (const [user, password] of Object.entries(credentials)) {
  if (!password) throw new Error(`bootstrap-mongo: falta la credencial de ${user}`)
}

let initialized = true
try {
  rs.status()
} catch (error) {
  if (error.codeName !== 'NotYetInitialized' && error.code !== 94) {
    throw error
  }
  initialized = false
}

if (!initialized) {
  const result = rs.initiate({
    _id: replicaSet,
    members: [{ _id: 0, host: replicaHost }],
  })
  if (result.ok !== 1) {
    throw new Error('No se pudo iniciar el replica set: ' + JSON.stringify(result))
  }
  print('replica set iniciado: ' + replicaSet + ' -> ' + replicaHost)
} else {
  const config = rs.conf()
  if (config._id !== replicaSet) {
    throw new Error(`Replica set inesperado: ${config._id}; se esperaba ${replicaSet}`)
  }
  if (config.members.length !== 1 || config.members[0].host !== replicaHost) {
    throw new Error(
      'La configuracion existente no coincide con el miembro aprobado: ' +
        JSON.stringify(config.members),
    )
  }
  print('replica set ya configurado; no se modifica')
}

let primary = false
for (let attempt = 0; attempt < 90; attempt += 1) {
  try {
    if (db.hello().isWritablePrimary === true) {
      primary = true
      break
    }
  } catch (_) {}
  sleep(1000)
}
if (!primary) {
  throw new Error('El replica set no eligio PRIMARY en 90s')
}

const identities = [
  {
    database: 'catalog',
    user: 'catalog-runtime',
    roles: [{ role: 'catalogRuntime', db: 'catalog' }],
  },
  {
    database: 'catalog',
    user: 'catalog-migration',
    roles: [
      { role: 'readWrite', db: 'catalog' },
      { role: 'dbAdmin', db: 'catalog' },
    ],
  },
  {
    database: 'player-inventory',
    user: 'inventory-runtime',
    roles: [{ role: 'readWrite', db: 'player-inventory' }],
  },
  {
    database: 'player-inventory',
    user: 'inventory-migration',
    roles: [
      { role: 'readWrite', db: 'player-inventory' },
      { role: 'dbAdmin', db: 'player-inventory' },
    ],
  },
]

const catalog = db.getSiblingDB('catalog')
const catalogRuntimePrivileges = [
  {
    resource: { db: 'catalog', collection: 'products' },
    actions: ['find', 'insert', 'update', 'remove'],
  },
  {
    resource: { db: 'catalog', collection: 'audit_log' },
    actions: ['find', 'insert'],
  },
  {
    resource: { db: 'catalog', collection: 'outbox' },
    actions: ['find', 'insert', 'update'],
  },
]
if (catalog.getRole('catalogRuntime')) {
  catalog.updateRole('catalogRuntime', { privileges: catalogRuntimePrivileges, roles: [] })
} else {
  catalog.createRole({
    role: 'catalogRuntime',
    privileges: catalogRuntimePrivileges,
    roles: [],
  })
}

for (const identity of identities) {
  const target = db.getSiblingDB(identity.database)
  if (target.getUser(identity.user)) {
    target.updateUser(identity.user, { pwd: credentials[identity.user], roles: identity.roles })
    print('identidad actualizada: ' + identity.user)
  } else {
    target.createUser({
      user: identity.user,
      pwd: credentials[identity.user],
      roles: identity.roles,
    })
    print('identidad creada: ' + identity.user)
  }
}

const status = rs.status()
const primaryCount = status.members.filter(member => member.stateStr === 'PRIMARY').length
if (status.members.length !== 1 || primaryCount !== 1) {
  throw new Error('Topologia inesperada: ' + JSON.stringify(status.members))
}

print(
  'MONGO_BOOTSTRAP_OK=' +
    JSON.stringify({ replicaSet, member: replicaHost, members: 1, primaryCount }),
)
