# Productos de recompensa de las misiones

Cómo se crean los productos que entregan las misiones de Missions y cómo se enlazan con su contenido. Estado al 2026-09-24, con el contenido v2: migraciones `010-playable-missions` y `012-content-v2`, cinco misiones. Diseño: [misiones-jugabilidad.md](../architecture/misiones-jugabilidad.md).

Missions no crea productos: guarda en su contenido el `productId` que entrega cada recompensa, y Player/Inventory lo acredita por `POST /api/internal/v1/inventory/grants` (HU-59, autorizado para `missions` en Player-Inventory #49). Así se entregan la épica del Máster (HU-73) y el botín del jefe (P-J1).

Los identificadores de los productos creados como datos **cambian en cada entorno**, así que el enlace se hace en cada entorno después de crearlos. Mientras un botín o una épica no tenga producto, Missions no lo promete en el detalle (P-J2) y su entrega espera sin inventar nada.

## Qué entrega cada misión

**Épicas de Máster: las 8 oficiales de la Tabla 20, una por Máster (P-J3).** Ya existen en el Catalog de producción (tipo `EPICA`) y no se crean:

| Épica | `epicRef` en el contenido | Máster (misión) | `productId` en producción |
| --- | --- | --- | --- |
| Toma y lleva | `toma-y-lleva` | Sombra del Olvido (Templo) | `0783a7ad-bb8a-463d-b24a-c4d88aae2d37` |
| Golpe de defensa | `golpe-de-defensa` | Coloso de Obsidiana (Templo) | `fc89342a-56b9-450f-9c5c-3ac2900c6fcb` |
| Frío concentrado | `frio-concentrado` | Hechicera del Sello (Cámara) | `3adf92bd-4806-4454-aacc-445ad016035d` |
| Segundo impulso | `segundo-impulso` | Campeón Carmesí (Arena) | `26dd2358-5ee9-4cf0-91d9-da02ba0d97ee` |
| Intimidación sangrienta | `intimidacion-sangrienta` | Filo Errante (Arena) | `f752f8a6-286d-4ede-b6ad-1cb9a7f43f00` |
| Luz cegadora | `luz-cegadora` | Llama Salvaje (Travesía) | `de662785-0edc-4816-b2bf-cbb785fdeaa1` |
| Té changua | `te-changua` | Chamán de la Niebla (Travesía) | `8ba12bc4-6baa-4f93-9afa-6ba52e750931` |
| Reanimador 3000 | `reanimador-3000` | Cirujano Silente (Travesía) | `840518a9-13c4-48de-89d3-faa05492598c` |

**Botín de los jefes: ocho productos.** Los cuatro primeros son de la primera versión; los cuatro últimos son del contenido v2. Los valores son una propuesta de balance que el PO puede ajustar; el cuerpo exacto para la API está en `scripts/misiones-productos-locales.cjs`.

| Producto | Etiqueta en el contenido | Tipo | Héroe compatible | Efectos | Créditos | Dónde cae |
| --- | --- | --- | --- | --- | --- | --- |
| Piel del Guardián | `Armadura «Piel del Guardián»` | `ARMADURA` (`CHEST`) | Guerrero Tanque | +2 Defensa, +2 Vida | 90 | Templo, 20 % |
| Espada del Templo | `Arma «Espada del Templo»` | `ARMA` | Guerrero Armas | +2 Ataque, +1 % de crítico | 110 | Templo, 15 % |
| Fragmento del Sello Antiguo | `Fragmento del Sello Antiguo` | `ITEM` | Todos | +1 Vida | 30 | Templo, 60 % en 3 tiradas; Camino, seguro |
| Núcleo del Sello | `Núcleo del Sello` | `ITEM` | Todos | +1 Poder | 60 | Cámara, 50 % |
| Emblema de la Arena | `Emblema de la Arena` | `ITEM` | Todos | +1 Ataque | 40 | Arena, 50 % |
| Guanteletes del Campeón | `Guanteletes del Campeón` | `ITEM` | Todos | +1 Ataque, +1 Defensa | 120 | Arena, 15 % |
| Esencia del Bosque | `Esencia del Bosque` | `ITEM` | Todos | +1 Vida | 25 | Travesía, 60 % en 2 tiradas |
| Amuleto de Raíz | `Amuleto de Raíz` | `ITEM` | Todos | +1 Defensa | 80 | Travesía, 20 % |

La dificultad sube estas probabilidades (+25 %, +50 % y +100 % en Heroico, Legendario y Mítico, con tope en el 100 %).

**Decisión pendiente del PO: visibilidad en la tienda.** Un producto recién creado queda activo y se puede comprar por su precio en créditos. Si el botín debe ser exclusivo de las misiones, hay que retirarlo de la venta desde la administración de Catalog, comprobando antes que el inventario siga mostrando los objetos ya entregados.

## Orden en producción

1. **Desplegar** Missions, Combat y Web con el contenido v2. El paso de migración aplica 011 y 012: 012 añade las tres misiones nuevas y mejora el Templo y la Cámara sin tocar lo que un administrador ya editó o enlazó.
2. **Crear los productos de botín que falten** en Web → Administración → Productos → Nuevo, con cuenta de administrador y MFA (Catalog exige `ADMINISTRATOR` y evidencia de segundo factor). Anotar el `productId` de cada uno.
3. **Enlazar el contenido** en Web → Editar misiones (`/admin/missions`), misión por misión:
   - `finalBoss.drops`: en cada objeto, el `productId` del producto que corresponde a su `label` (tabla de botín).
   - `masterEncounter.candidates[].epic.productId`: el de la tabla de épicas, según su `epicRef`.
   - Si el Templo aún trae la épica `velo-de-sombras` (una base que no pasó por 012 y que un administrador editó), reemplazar el bloque `epic` de la Sombra del Olvido por el de abajo.
4. **Verificar.**
   - `GET /api/v1/missions/{id}` de cada misión muestra sus épicas y su botín en `rewards` (P-J2). Lo que no aparece es lo que falta enlazar.
   - `GET /api/v1/missions/me/history/summary` trae las ocho épicas en `epicAlbum`.
   - Al cerrarse una misión, el reporte muestra el botín y la épica `CREDITED` y el inventario del jugador los recibe.

```json
"epic": {
  "name": "Toma y lleva",
  "epicRef": "toma-y-lleva",
  "productId": "0783a7ad-bb8a-463d-b24a-c4d88aae2d37",
  "generalEffect": "+1 al ataque para todos los héroes.",
  "epicEffect": "Solo Pícaro Veneno: disminuye a la mitad el daño causado por el oponente y se lo retorna."
}
```

Missions lee el contenido al simular una misión, no al matricularla: una misión que ya se simuló conserva los productos con los que se simuló.

## Entorno local

Con el stack de `compose/` levantado (`AUTH_MODE=disabled`, así que Catalog y Missions aceptan sus rutas de administración sin testimonio):

```bash
OUT=productos.json node scripts/misiones-productos-locales.cjs
IDS=productos.json node scripts/misiones-enlazar-productos.cjs
```

- Los dos scripts son idempotentes.
- El Catalog local no trae las épicas oficiales, así que el primero crea copias de las 8 con el mismo nombre, efectos, precio y tiraje que en producción, además de los 8 objetos de botín. Las copias no llevan `powerCost` ni `cooldownTurns` porque el Catalog de `develop` los rechaza (400).
- El segundo enlaza todo el botín por etiqueta y cada épica por su `epicRef`.
- Hay que volver a ejecutarlos después de reiniciar la base de Missions, porque las migraciones siembran el contenido sin `productId`.
