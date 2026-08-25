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
// Las contrasenas son de ejemplo. Deben sustituirse antes de cualquier uso
// que no sea desarrollo local.

const servicios = [
  { base: 'player-inventory', usuario: 'inventory' },
  { base: 'catalog', usuario: 'catalog' },
]

for (const servicio of servicios) {
  db.getSiblingDB(servicio.base).createUser({
    user: servicio.usuario,
    pwd: 'cambiar',
    // `readWrite` acotado a su propia base. No se concede `dbAdmin` ni
    // `readWriteAnyDatabase`: un servicio no necesita administrar el motor
    // ni leer nada fuera de su frontera.
    roles: [{ role: 'readWrite', db: servicio.base }],
  })
  print('usuario creado: ' + servicio.usuario + ' -> ' + servicio.base)
}
