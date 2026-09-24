#!/usr/bin/env node
/*
 * Enlaza en el contenido local de Missions la epica oficial del Master y el botin con sus productos.
 *
 * SOLO PARA EL ENTORNO LOCAL (`compose/` con AUTH_MODE=disabled): Catalog y Missions
 * aceptan ahi las rutas de administracion sin testimonio. En produccion la carga se
 * hace desde la administracion de Web, con cuenta de administrador y MFA: ver
 * docs/runbooks/misiones-productos-de-recompensa.md.
 *
 * Uso:
 *   IDS=productos.json node scripts/misiones-enlazar-productos.cjs
 *   Se repite despues de reiniciar la base de Missions: la migracion 010 siembra el contenido sin productId.
 */
const fs = require('fs')
const BASE = process.env.BASE ?? 'http://localhost:8080/api'
const ids = JSON.parse(fs.readFileSync(process.env.IDS, 'utf8'))
const DROPS = {
  'Fragmento del Sello Antiguo': ids['Fragmento del Sello Antiguo'],
  'Armadura «Piel del Guardián»': ids['Piel del Guardián'],
  'Arma «Espada del Templo»': ids['Espada del Templo'],
  'Núcleo del Sello': ids['Núcleo del Sello'],
}
const EPIC = {
  name: 'Toma y lleva',
  epicRef: 'toma-y-lleva',
  productId: ids['Toma y lleva'],
  generalEffect: '+1 al ataque para todos los héroes.',
  epicEffect: 'Solo Pícaro Veneno: disminuye a la mitad el daño causado por el oponente y se lo retorna.',
}
const main = async () => {
  const missions = await (await fetch(`${BASE}/v1/admin/missions`)).json()
  for (const mission of missions) {
    const next = structuredClone(mission)
    for (const drop of next.finalBoss?.drops ?? []) {
      if (DROPS[drop.label] === undefined) throw new Error(`${mission.missionId}: botín sin producto: ${drop.label}`)
      drop.productId = DROPS[drop.label]
    }
    for (const candidate of next.masterEncounter?.candidates ?? []) {
      if (candidate.subtype === 'PICARO_VENENO') candidate.epic = { ...candidate.epic, ...EPIC }
    }
    const res = await fetch(`${BASE}/v1/admin/missions/${encodeURIComponent(mission.missionId)}`, {
      method: 'PUT', headers: { 'content-type': 'application/json' }, body: JSON.stringify(next),
    })
    const text = await res.text()
    if (!res.ok) throw new Error(`${mission.missionId}: HTTP ${res.status} ${text.slice(0, 300)}`)
    console.log(`${mission.missionId}: actualizada (HTTP ${res.status})`)
  }
  const after = await (await fetch(`${BASE}/v1/admin/missions`)).json()
  for (const m of after) {
    console.log(`## ${m.missionId}`)
    for (const c of m.masterEncounter?.candidates ?? []) console.log(`   Máster ${c.name}: épica ${c.epic.name} -> ${c.epic.productId}`)
    for (const d of m.finalBoss?.drops ?? []) console.log(`   botín ${d.label} -> ${d.productId}`)
  }
}
main().catch((error) => { console.error(error.message); process.exitCode = 1 })
