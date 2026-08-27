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
]

for (const servicio of servicios) {
  db.getSiblingDB(servicio.base).createUser({
    user: servicio.usuario,
    pwd: clave,
    // `readWrite` acotado a su propia base. No se concede `dbAdmin` ni
    // `readWriteAnyDatabase`: un servicio no necesita administrar el motor
    // ni leer nada fuera de su frontera.
    roles: [{ role: 'readWrite', db: servicio.base }],
  })
  print('usuario creado: ' + servicio.usuario + ' -> ' + servicio.base)
}
