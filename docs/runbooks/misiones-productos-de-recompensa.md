# Productos de recompensa de las misiones

Cómo se crean los productos que entregan las dos misiones jugables de Missions (migración
`010-playable-missions`) y cómo se enlazan con su contenido. Estado al 2026-09-24.

Missions no crea productos: guarda en su contenido el `productId` que entrega cada recompensa, y
Player/Inventory lo acredita por `POST /api/internal/v1/inventory/grants` (HU-59, autorizado para
`missions` en Player-Inventory #49). Los identificadores **cambian en cada entorno**, porque los
productos se crean como datos, así que el enlace se hace en cada entorno después de crearlos.

## Qué entrega cada misión

**Épica del Máster: la oficial de la Tabla 20 para su tipo de héroe.** «Sombra del Olvido», el
Máster de «El Templo Olvidado», es Pícaro Veneno, así que entrega **«Toma y lleva»**. Esa épica
ya existe en el Catalog de producción (tipo `EPICA`, `productId`
`0783a7ad-bb8a-463d-b24a-c4d88aae2d37`): no se crea. «La Cámara Sellada» no tiene Máster.

**Botín del jefe: cuatro productos nuevos.** Los valores son una propuesta de balance que el PO
puede ajustar; el cuerpo exacto para la API está en `scripts/misiones-productos-locales.cjs`.

| Producto | Tipo | Héroe compatible | Efectos | Créditos | Tiraje | Dónde cae |
| --- | --- | --- | --- | --- | --- | --- |
| Piel del Guardián | `ARMADURA` (ranura `CHEST`) | Guerrero Tanque | +2 Defensa, +2 Vida | 90 | ilimitado | Templo, 20 % |
| Espada del Templo | `ARMA` | Guerrero Armas | +2 Ataque, +1 % de crítico | 110 | ilimitado | Templo, 15 % |
| Fragmento del Sello Antiguo | `ITEM` | Todos (`ALL_HEROES`) | +1 Vida | 30 | ilimitado | Templo, 60 % en 3 tiradas |
| Núcleo del Sello | `ITEM` | Todos (`ALL_HEROES`) | +1 Poder | 60 | ilimitado | Cámara, 50 % |

**Decisión pendiente del PO: visibilidad en la tienda.** Un producto recién creado queda activo y
se puede comprar por su precio en créditos. Si el botín debe ser exclusivo de las misiones, hay que
retirarlo de la venta desde la administración de Catalog, comprobando antes que el inventario siga
mostrando los objetos ya entregados.

## Orden en producción

1. **Desplegar lo que ya está en `develop`.** Promover a `main` y desplegar Missions (#15: contenido
   editable y migración 010), Web (#150: editor de misiones), Combat (#44 y #50),
   Player-Inventory (#49) e Infrastructure (#160). Sin el editor desplegado no hay dónde enlazar.
2. **Crear los cuatro productos** en Web → Administración → Productos → Nuevo, con cuenta de
   administrador y MFA (Catalog exige `ADMINISTRATOR` y evidencia de segundo factor). Anotar el
   `productId` de cada uno.
3. **Enlazar el contenido** en Web → Editar misiones (`/admin/missions`):
   - «El Templo Olvidado», `masterEncounter.candidates` → «Sombra del Olvido»: reemplazar `epic`
     por el bloque de abajo.
   - «El Templo Olvidado», `finalBoss.drops`: poner en cada objeto el `productId` que corresponde a
     su `label` (`Fragmento del Sello Antiguo`, `Armadura «Piel del Guardián»`,
     `Arma «Espada del Templo»`).
   - «La Cámara Sellada», `finalBoss.drops`: el `productId` de `Núcleo del Sello`.
4. **Verificar.**
   - `GET /api/v1/missions/msn_templo_olvidado` muestra «Toma y lleva» como épica del Máster.
   - Al cerrarse una misión con el Máster derrotado, el reporte muestra la épica `CREDITED` y el
     inventario del jugador la recibe; igual con el botín que haya caído.

```json
"epic": {
  "name": "Toma y lleva",
  "epicRef": "toma-y-lleva",
  "productId": "0783a7ad-bb8a-463d-b24a-c4d88aae2d37",
  "generalEffect": "+1 al ataque para todos los héroes.",
  "epicEffect": "Solo Pícaro Veneno: disminuye a la mitad el daño causado por el oponente y se lo retorna."
}
```

Missions lee el contenido al simular una misión, no al matricularla: una misión que ya se simuló
conserva los productos con los que se simuló.

## Entorno local

Con el stack de `compose/` levantado (`AUTH_MODE=disabled`, así que Catalog y Missions aceptan sus
rutas de administración sin testimonio):

```bash
OUT=productos.json node scripts/misiones-productos-locales.cjs
IDS=productos.json node scripts/misiones-enlazar-productos.cjs
```

Los dos scripts son idempotentes. El Catalog local no trae las épicas oficiales, así que el primero
crea también una copia de «Toma y lleva» con los mismos atributos que en producción. Hay que
volver a ejecutarlos después de reiniciar la base de Missions, porque la migración 010 siembra el
contenido sin `productId`.
