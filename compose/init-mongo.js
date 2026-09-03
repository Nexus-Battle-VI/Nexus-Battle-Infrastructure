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
// La contrasena NO esta escrita aqui: llega en `DB_PASSWORD`, del entorno del
// contenedor. Antes era la palabra literal `cambiar`, y eso significaba que
// `MONGO_INITDB_ROOT_PASSWORD` recibia la contrasena buena mientras los dos
// usuarios que de verdad usan los servicios se quedaban con una conocida.
//
// ATENCION: esto se ejecuta UNA sola vez, sobre un directorio de datos vacio.
// Cambiar este fichero no cambia las credenciales de un volumen ya creado.

const clave = process.env.DB_PASSWORD

if (!clave) {
  throw new Error('init-mongo: DB_PASSWORD no esta definida. Se aborta la inicializacion.')
}

const servicios = [
  { base: 'player-inventory', usuario: 'inventory' },
  { base: 'catalog', usuario: 'catalog' },
  { base: 'notifications', usuario: 'notifications' },
]

for (const servicio of servicios) {
  db.getSiblingDB(servicio.base).createUser({
    user: servicio.usuario,
    pwd: clave,
    // Dos roles, los DOS acotados a su propia base.
    //
    // `readWrite` para los datos. `dbAdmin` para el ESQUEMA: declarar un
    // validador con `collMod` no esta en `readWrite`, y las migraciones de
    // Catalog (`002-premium-products`, `003-premium-product-validation`) lo
    // usan. Sin el, la migracion falla con «not authorized on catalog to
    // execute command { collMod: ... }» — comprobado en el nodo real, no
    // supuesto.
    //
    // No se detectaba en las pruebas porque Testcontainers levanta Mongo SIN
    // autenticacion: el permiso no llegaba a ejercitarse nunca.
    //
    // Sigue sin concederse nada fuera de su frontera: ni `dbAdminAnyDatabase`,
    // ni `readWriteAnyDatabase`, ni `userAdmin`. Un servicio administra el
    // esquema de SU base, que es justo lo que significa ser su propietario, y
    // no puede tocar la de otro ni gestionar usuarios.
    roles: [
      { role: 'readWrite', db: servicio.base },
      { role: 'dbAdmin', db: servicio.base },
    ],
  })
  print('usuario creado: ' + servicio.usuario + ' -> ' + servicio.base)
}
