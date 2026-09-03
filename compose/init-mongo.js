// Inicializacion de MongoDB para la composicion de referencia.
//
// Equivalente exacto de init-postgres.sql: cada servicio recibe credenciales
// propias con permiso SOLO sobre su propia base de datos.
//
// Sin este fichero, Mongo arranca sin autenticacion y la separacion entre
// `catalog` y `player-inventory` seria unicamente una convencion de nombres:
// cualquiera de los dos servicios podria leer y escribir la base del otro.
// La regla de propiedad de datos dejaria de estar aplicada y pasaria a estar
// solo documentada, que no es lo mismo.
//
// Las cuatro contrasenas NO estan escritas aqui: llegan en variables separadas
// del entorno. Reutilizar DB_PASSWORD permitiria a runtime autenticarse como
// migracion y obtener dbAdmin, anulando la separacion de identidades.
//
// ATENCION: esto se ejecuta UNA sola vez, sobre un directorio de datos vacio.
// Cambiar este fichero no cambia las credenciales de un volumen ya creado.

const credenciales = {
  'catalog-runtime': process.env.MONGO_CATALOG_RUNTIME_PASSWORD,
  'catalog-migration': process.env.MONGO_CATALOG_MIGRATION_PASSWORD,
  'inventory-runtime': process.env.MONGO_INVENTORY_RUNTIME_PASSWORD,
  'inventory-migration': process.env.MONGO_INVENTORY_MIGRATION_PASSWORD,
}

for (const [usuario, clave] of Object.entries(credenciales)) {
  if (!clave) {
    throw new Error(`init-mongo: falta la credencial de ${usuario}`)
  }
}

const catalog = db.getSiblingDB('catalog')
catalog.createRole({
  role: 'catalogRuntime',
  privileges: [
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
  ],
  roles: [],
})

const identidades = [
  {
    base: 'player-inventory',
    usuario: 'inventory-runtime',
    roles: [{ role: 'readWrite', db: 'player-inventory' }],
  },
  {
    base: 'player-inventory',
    usuario: 'inventory-migration',
    roles: [
      { role: 'readWrite', db: 'player-inventory' },
      { role: 'dbAdmin', db: 'player-inventory' },
    ],
  },
  {
    base: 'catalog',
    usuario: 'catalog-runtime',
    roles: [{ role: 'catalogRuntime', db: 'catalog' }],
  },
  {
    base: 'catalog',
    usuario: 'catalog-migration',
    roles: [
      { role: 'readWrite', db: 'catalog' },
      { role: 'dbAdmin', db: 'catalog' },
    ],
  },
]

for (const identidad of identidades) {
  db.getSiblingDB(identidad.base).createUser({
    user: identidad.usuario,
    pwd: credenciales[identidad.usuario],
    roles: identidad.roles,
  })
  print('identidad creada: ' + identidad.usuario + ' -> ' + identidad.base)
}
