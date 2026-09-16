// Usuario de MongoDB para Combat, contexto de Sprint 2 (ADR-019).
//
// Fichero aparte de `init-mongo.js` por el mismo motivo que
// `init-postgres-sprint-2.sh`: `init-mongo.js` viaja en el `user_data` del nodo
// `data`, cambiarlo reemplaza ese nodo, y sobre un volumen ya inicializado no
// volveria a ejecutarse. Este no viaja en `user_data`.
//
// IDEMPOTENTE: se monta en `docker-entrypoint-initdb.d` para volumenes vacios y
// se ejecuta a mano sobre el nodo `data` existente (ver
// `docs/runbooks/desplegar-contextos-sprint-2.md`). Mismos roles que el resto
// de servicios: `readWrite` y `dbAdmin`, acotados a su propia base.

const clave = process.env.DB_PASSWORD

if (!clave) {
  throw new Error('init-mongo-sprint-2: DB_PASSWORD no esta definida. Se aborta.')
}

const servicios = [{ base: 'combat', usuario: 'combat' }]

for (const servicio of servicios) {
  const base = db.getSiblingDB(servicio.base)

  if (base.getUser(servicio.usuario) === null) {
    base.createUser({
      user: servicio.usuario,
      pwd: clave,
      roles: [
        { role: 'readWrite', db: servicio.base },
        { role: 'dbAdmin', db: servicio.base },
      ],
    })
    print('usuario creado: ' + servicio.usuario + ' -> ' + servicio.base)
  } else {
    print('usuario ya existia: ' + servicio.usuario + ' -> ' + servicio.base)
  }

  // La salida es la comprobacion: los roles reales, leidos del motor.
  print(servicio.usuario + ' roles: ' + JSON.stringify(base.getUser(servicio.usuario).roles))
}
