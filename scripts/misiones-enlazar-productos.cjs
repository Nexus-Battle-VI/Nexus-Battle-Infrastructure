#!/usr/bin/env node
/*
 * Enlaza en el contenido local de Missions cada epica de Master y cada botin de jefe con su producto.
 *
 * SOLO PARA EL ENTORNO LOCAL (`compose/` con AUTH_MODE=disabled): Catalog y Missions
 * aceptan ahi las rutas de administracion sin testimonio. En produccion la carga se
 * hace desde la administracion de Web, con cuenta de administrador y MFA: ver
 * docs/runbooks/misiones-productos-de-recompensa.md.
 *
 * Uso:
 *   IDS=productos.json node scripts/misiones-enlazar-productos.cjs
 *   IDS es la salida de scripts/misiones-productos-locales.cjs (nombre de producto -> productId).
 *   Se repite despues de reiniciar la base de Missions: las migraciones 010 y 012 siembran el
 *   contenido sin productId. Es idempotente.
 */
const fs = require('fs')
const BASE = process.env.BASE ?? 'http://localhost:8080/api'
const ids = JSON.parse(fs.readFileSync(process.env.IDS, 'utf8'))

/** Etiqueta del botin en el contenido -> nombre del producto en Catalog. */
const DROPS = {
  'Fragmento del Sello Antiguo': 'Fragmento del Sello Antiguo',
  'Armadura «Piel del Guardián»': 'Piel del Guardián',
  'Arma «Espada del Templo»': 'Espada del Templo',
  'Núcleo del Sello': 'Núcleo del Sello',
  'Emblema de la Arena': 'Emblema de la Arena',
  'Guanteletes del Campeón': 'Guanteletes del Campeón',
  'Esencia del Bosque': 'Esencia del Bosque',
  'Amuleto de Raíz': 'Amuleto de Raíz',
}

/** Epica del contenido (epicRef) -> nombre del producto: las 8 oficiales de la Tabla 20. */
const EPICS = {
  'golpe-de-defensa': 'Golpe de defensa',
  'segundo-impulso': 'Segundo impulso',
  'luz-cegadora': 'Luz cegadora',
  'frio-concentrado': 'Frio concentrado',
  'toma-y-lleva': 'Toma y lleva',
  'intimidacion-sangrienta': 'Intimidación sangrienta',
  'te-changua': 'Té changua',
  'reanimador-3000': 'Reanimador 3000',
}

/** Un Templo todavia en v1 (sin la migracion 012) trae la epica del ejemplo del curso. */
const TOMA_Y_LLEVA = {
  name: 'Toma y lleva',
  epicRef: 'toma-y-lleva',
  generalEffect: '+1 al ataque para todos los héroes.',
  epicEffect: 'Solo Pícaro Veneno: disminuye a la mitad el daño causado por el oponente y se lo retorna.',
}

const productOf = (name, where) => {
  const productId = ids[name]
  if (productId === undefined) throw new Error(`${where}: falta el producto «${name}» en ${process.env.IDS}`)
  return productId
}

const main = async () => {
  const missions = await (await fetch(`${BASE}/v1/admin/missions`)).json()
  for (const mission of missions) {
    const next = structuredClone(mission)
    for (const drop of next.finalBoss?.drops ?? []) {
      const name = DROPS[drop.label]
      if (name === undefined) throw new Error(`${mission.missionId}: botín sin producto: ${drop.label}`)
      drop.productId = productOf(name, mission.missionId)
    }
    for (const candidate of next.masterEncounter?.candidates ?? []) {
      if (candidate.epic.epicRef === 'velo-de-sombras' && candidate.subtype === 'PICARO_VENENO') {
        candidate.epic = { ...candidate.epic, ...TOMA_Y_LLEVA }
      }
      const name = EPICS[candidate.epic.epicRef]
      if (name === undefined) throw new Error(`${mission.missionId}: épica sin producto: ${candidate.epic.epicRef}`)
      candidate.epic = { ...candidate.epic, productId: productOf(name, mission.missionId) }
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
