#!/usr/bin/env node
/*
 * Crea en el Catalog local los productos de recompensa de las misiones (idempotente por nombre).
 *
 * SOLO PARA EL ENTORNO LOCAL (`compose/` con AUTH_MODE=disabled): Catalog y Missions
 * aceptan ahi las rutas de administracion sin testimonio. En produccion la carga se
 * hace desde la administracion de Web, con cuenta de administrador y MFA: ver
 * docs/runbooks/misiones-productos-de-recompensa.md.
 *
 * Contenido v2 de Missions (migracion 012): las 8 epicas oficiales de la Tabla 20, una por
 * Master, y el botin de los jefes de las cinco misiones.
 *
 * Uso:
 *   OUT=productos.json node scripts/misiones-productos-locales.cjs
 *   BASE (opcional) = origen de la API; por defecto http://localhost:8080/api
 */
const BASE = process.env.BASE ?? 'http://localhost:8080/api'
const self = (statistic, amount, mode = 'FIXED') => ({
  target: 'SELF', kind: 'STAT_MODIFIER', statistic, operation: 'INCREASE',
  magnitude: mode === 'FIXED' ? { mode, amount } : { mode, basisPoints: amount },
})
const fixed = (amount) => ({ mode: 'FIXED', amount })

/**
 * Epicas oficiales de la Tabla 20: copia de los productos de produccion, con su mismo
 * nombre, efectos, precio y tiraje. El Catalog local no las trae. Van sin `powerCost` ni
 * `cooldownTurns`: produccion los tiene, pero el Catalog de `develop` los rechaza (400).
 */
const epic = (name, subtype, description, values) => ({
  name, type: 'EPICA', printRun: -1, creditsPrice: 0, premium: true,
  realMoneyPrice: { amount: 6000000, currency: 'COP' }, description,
  attributes: { schemaVersion: '1', values: { kind: 'EPICA', compatibleHeroSubtype: subtype, ...values } },
})
const EPICS = [
  epic('Golpe de defensa', 'GUERRERO_TANQUE',
    'General: +1 al ataque. Especifico Guerrero Tanque: +4 al daño +2% de crítico.',
    { generalEffect: { ...self('ATTACK', 1), stackable: false },
      specificEffect: { ...self('DAMAGE', 4), stackable: false } }),
  epic('Segundo impulso', 'GUERRERO_ARMAS',
    'General: recupera 1d4 de vida. Especifico Guerrero Armas: +3 a la vida +5% de crítico.',
    { generalEffect: { target: 'SELF', stackable: false, kind: 'HEALING', magnitude: { mode: 'DICE', count: 1, sides: 4 } },
      specificEffect: { ...self('HEALTH', 3), stackable: false } }),
  epic('Luz cegadora', 'MAGO_FUEGO',
    'General: +1 a la vida. Especifico Mago Fuego: +2 al daño +1% de crítico.',
    { generalEffect: { ...self('HEALTH', 1), stackable: false },
      specificEffect: { ...self('DAMAGE', 2), stackable: false } }),
  epic('Frio concentrado', 'MAGO_HIELO',
    'General: -1 de poder al oponente. Especifico Mago Hielo: no recibe ningún daño en el siguiente turno.',
    { generalEffect: { target: 'OPPONENT', stackable: false, kind: 'STAT_MODIFIER', statistic: 'POWER', operation: 'DECREASE', magnitude: fixed(1) },
      specificEffect: { target: 'SELF', durationTurns: 1, stackable: false, kind: 'IMMUNITY', immunityCode: 'TODO_DANIO' } }),
  epic('Toma y lleva', 'PICARO_VENENO',
    'General: +1 al ataque. Especifico Pícaro Veneno: disminuye a la mitad el daño causado por el oponente y se lo retorna.',
    { generalEffect: { ...self('ATTACK', 1), stackable: false },
      specificEffect: { target: 'OPPONENT', stackable: false, kind: 'REFLECT_DAMAGE', magnitude: { mode: 'PERCENTAGE', basisPoints: 5000 } } }),
  epic('Intimidación sangrienta', 'PICARO_MACHETE',
    'General: +2 al ataque. Especifico Pícaro Machete: +2 a la vida +2% de crítico.',
    { generalEffect: { ...self('ATTACK', 2), stackable: false },
      specificEffect: { ...self('HEALTH', 2), stackable: false } }),
  epic('Té changua', 'CHAMAN',
    'General: sana a todos +(4d8). Especifico Chamán: se asocia con un compañero; si este fallece, se reanima con el 20% de su salud.',
    { generalEffect: { target: 'ALLIED_GROUP', stackable: false, kind: 'HEALING', magnitude: { mode: 'DICE', count: 4, sides: 8 } },
      specificEffect: { target: 'ALLY', stackable: false, kind: 'REVIVE', magnitude: { mode: 'PERCENTAGE', basisPoints: 2000 } } }),
  epic('Reanimador 3000', 'MEDICO',
    'Sin efecto general (no aplica). Especifico Médico: se asocia con un compañero; si este fallece, se reanima con el 20% de su salud.',
    { specificEffect: { target: 'ALLY', stackable: false, kind: 'REVIVE', magnitude: { mode: 'PERCENTAGE', basisPoints: 2000 } } }),
]

const item = (name, creditsPrice, description, effects) => ({
  name, type: 'ITEM', printRun: -1, creditsPrice, premium: false, description,
  attributes: { schemaVersion: '1', values: { kind: 'ITEM', compatibilityScope: 'ALL_HEROES', effects } },
})
const LOOT = [
  { name: 'Piel del Guardián', type: 'ARMADURA', printRun: -1, creditsPrice: 90, premium: false,
    description: 'Armadura hecha con la piel pétrea del Guardián Eterno. Botín del Templo Olvidado.',
    attributes: { schemaVersion: '1', values: { kind: 'ARMADURA', compatibilityScope: 'SELECTED_SUBTYPES',
      compatibleHeroSubtypes: ['GUERRERO_TANQUE'], effects: [self('DEFENSE', 2), self('HEALTH', 2)], slot: 'CHEST' } } },
  { name: 'Espada del Templo', type: 'ARMA', printRun: -1, creditsPrice: 110, premium: false,
    description: 'Hoja ceremonial custodiada en la cámara mayor del Templo Olvidado.',
    attributes: { schemaVersion: '1', values: { kind: 'ARMA', compatibilityScope: 'SELECTED_SUBTYPES',
      compatibleHeroSubtypes: ['GUERRERO_ARMAS'], effects: [self('ATTACK', 2), self('CRITICAL_CHANCE', 100, 'PERCENTAGE')] } } },
  item('Fragmento del Sello Antiguo', 30,
    'Uno de los tres fragmentos del sello que protege el Templo Olvidado.', [self('HEALTH', 1)]),
  item('Núcleo del Sello', 60,
    'Corazón del sello de la Cámara Sellada; todavía conserva su energía.', [self('POWER', 1)]),
  item('Emblema de la Arena', 40,
    'Distintivo de quien sobrevivió a las tres oleadas de la Arena de los Caídos.', [self('ATTACK', 1)]),
  item('Guanteletes del Campeón', 120,
    'Guanteletes de Varkas, el Invicto. Pocos los han visto de cerca.', [self('ATTACK', 1), self('DEFENSE', 1)]),
  item('Esencia del Bosque', 25,
    'Savia luminosa que la Bruja del Pantano guardaba en frascos.', [self('HEALTH', 1)]),
  item('Amuleto de Raíz', 80,
    'Raíz tallada que protege a quien cruza el Bosque Sombrío.', [self('DEFENSE', 1)]),
]
const PRODUCTS = [...EPICS, ...LOOT]

const json = async (res) => { const text = await res.text(); try { return JSON.parse(text) } catch { return text } }
const main = async () => {
  const existing = []
  for (let page = 1; page <= 20; page += 1) {
    const body = await json(await fetch(`${BASE}/v1/catalog/products?page=${page}`))
    existing.push(...(body.items ?? []))
    if ((body.items ?? []).length === 0 || existing.length >= body.total) break
  }
  const imageOf = (type) => (existing.find((p) => p.type === type) ?? existing[0]).imageUrl
  const result = {}
  for (const product of PRODUCTS) {
    const found = existing.find((p) => p.name === product.name)
    if (found) { result[product.name] = found.productId; console.log(`ya existía: ${product.name} -> ${found.productId}`); continue }
    const res = await fetch(`${BASE}/v1/catalog/products`, { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ ...product, imageUrl: imageOf(product.type) }) })
    const body = await json(res)
    if (!res.ok) throw new Error(`${product.name}: HTTP ${res.status} ${JSON.stringify(body)}`)
    result[product.name] = body.productId
    console.log(`creado: ${product.name} [${product.type}] -> ${body.productId}`)
  }
  require('fs').writeFileSync(process.env.OUT, JSON.stringify(result, null, 1))
}
main().catch((error) => { console.error(error.message); process.exit(1) })
