#!/usr/bin/env node
/*
 * Crea en el Catalog local los productos de recompensa de las misiones (idempotente por nombre).
 *
 * SOLO PARA EL ENTORNO LOCAL (`compose/` con AUTH_MODE=disabled): Catalog y Missions
 * aceptan ahi las rutas de administracion sin testimonio. En produccion la carga se
 * hace desde la administracion de Web, con cuenta de administrador y MFA: ver
 * docs/runbooks/misiones-productos-de-recompensa.md.
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
const PRODUCTS = [
  { // Épica oficial de la Tabla 20 (copia fiel de la de producción).
    name: 'Toma y lleva', type: 'EPICA', printRun: -1, creditsPrice: 0, premium: true,
    realMoneyPrice: { amount: 6000000, currency: 'COP' },
    description: 'General: +1 al ataque. Especifico Pícaro Veneno: disminuye a la mitad el daño causado por el oponente y se lo retorna.',
    attributes: { schemaVersion: '1', values: { kind: 'EPICA', compatibleHeroSubtype: 'PICARO_VENENO',
      generalEffect: self('ATTACK', 1),
      specificEffect: { target: 'OPPONENT', kind: 'REFLECT_DAMAGE', magnitude: { mode: 'PERCENTAGE', basisPoints: 5000 } },
      } },
  },
  { name: 'Piel del Guardián', type: 'ARMADURA', printRun: -1, creditsPrice: 90, premium: false,
    description: 'Armadura hecha con la piel pétrea del Guardián Eterno. Botín del Templo Olvidado.',
    attributes: { schemaVersion: '1', values: { kind: 'ARMADURA', compatibilityScope: 'SELECTED_SUBTYPES',
      compatibleHeroSubtypes: ['GUERRERO_TANQUE'], effects: [self('DEFENSE', 2), self('HEALTH', 2)], slot: 'CHEST' } } },
  { name: 'Espada del Templo', type: 'ARMA', printRun: -1, creditsPrice: 110, premium: false,
    description: 'Hoja ceremonial custodiada en la cámara mayor del Templo Olvidado.',
    attributes: { schemaVersion: '1', values: { kind: 'ARMA', compatibilityScope: 'SELECTED_SUBTYPES',
      compatibleHeroSubtypes: ['GUERRERO_ARMAS'], effects: [self('ATTACK', 2), self('CRITICAL_CHANCE', 100, 'PERCENTAGE')] } } },
  { name: 'Fragmento del Sello Antiguo', type: 'ITEM', printRun: -1, creditsPrice: 30, premium: false,
    description: 'Uno de los tres fragmentos del sello que protege el Templo Olvidado.',
    attributes: { schemaVersion: '1', values: { kind: 'ITEM', compatibilityScope: 'ALL_HEROES', effects: [self('HEALTH', 1)] } } },
  { name: 'Núcleo del Sello', type: 'ITEM', printRun: -1, creditsPrice: 60, premium: false,
    description: 'Corazón del sello de la Cámara Sellada; todavía conserva su energía.',
    attributes: { schemaVersion: '1', values: { kind: 'ITEM', compatibilityScope: 'ALL_HEROES', effects: [self('POWER', 1)] } } },
]
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
