# Estimación de coste — Recursos visuales de Producto en S3

> Estimación para EN-027.3 #283. No es una factura ni autoriza provisionar.

- Región: `us-east-1`.
- Clase: S3 Standard.
- Sin CloudFront, KMS, Transfer Acceleration ni replicación.
- Precios de referencia consultados el 2026-09-02.
- No se asume capa gratuita de almacenamiento o solicitudes.

Fuentes: [precios oficiales de S3](https://aws.amazon.com/s3/pricing/),
[precios de transferencia de AWS](https://aws.amazon.com/ec2/pricing/on-demand/)
y [documentación de URL firmadas](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-presigned-url.html).

## Precios usados

| Concepto | Precio |
| --- | ---: |
| S3 Standard, primeros 50 TB | USD 0,023 por GB-mes |
| PUT/COPY/POST/LIST | USD 0,005 por 1 000 solicitudes |
| GET y otras lecturas | USD 0,0004 por 1 000 solicitudes |
| Transferencia entrante | USD 0 |
| S3 hacia servicios AWS en la misma región | USD 0 |
| Salida a Internet | primeros 100 GB/mes sin cargo, agregados entre servicios; después, sensibilidad a USD 0,09/GB |

La franquicia de transferencia no se presenta como “gratis para siempre”:
compite con la salida de los demás servicios de la cuenta.

## Escenario de demo

| Supuesto mensual | Cantidad |
| --- | ---: |
| Assets almacenados | 5 GB |
| Operaciones PUT/COPY/POST/LIST | 10 000 |
| Operaciones GET | 100 000 |
| Salida a Internet | 10 GB |
| Staging abandonado | eliminado al día siguiente |
| Versiones no vigentes | 30 días, salvo referencias de HU-37 |

Cálculo:

| Partida | Fórmula | USD/mes |
| --- | --- | ---: |
| Almacenamiento | 5 × 0,023 | 0,115 |
| Escrituras | 10 000 / 1 000 × 0,005 | 0,050 |
| Lecturas | 100 000 / 1 000 × 0,0004 | 0,040 |
| Salida dentro de franquicia agregada | 10 × 0 | 0,000 |
| **Total estimado** | | **0,205** |

Redondeado: **USD 0,21/mes** antes de impuestos.

Si los 100 GB sin cargo ya estuvieran consumidos por otros servicios, 10 GB de
salida añadirían USD 0,90 y el total sería **USD 1,11/mes**.

## Escenario de sensibilidad

| Supuesto mensual | Cantidad |
| --- | ---: |
| Almacenamiento | 50 GB |
| Escrituras | 100 000 |
| Lecturas | 1 000 000 |
| Salida facturable, después de la franquicia | 100 GB |

| Partida | USD/mes |
| --- | ---: |
| Almacenamiento | 1,15 |
| Escrituras | 0,50 |
| Lecturas | 0,40 |
| Salida | 9,00 |
| **Total** | **11,05** |

Sumado al máximo 24/7 documentado actualmente para la demo (USD 36,53), el
escenario de sensibilidad daría aproximadamente **USD 47,58/mes**, todavía bajo
el techo de USD 100. No incluye impuestos ni otros servicios nuevos.

## Variable dominante y controles

La transferencia domina en cuanto se supera la franquicia agregada. Se requiere:

- etiqueta de costo específica del bucket;
- métrica de bytes de salida y almacenamiento;
- alerta operativa al superar 5 GB almacenados o 50 GB de salida mensual;
- comparación mensual de costo real contra esta estimación;
- revisión previa si se propone CloudFront, KMS, replicación o una región nueva.

El versionado puede multiplicar almacenamiento. Las claves funcionales son
inmutables y las versiones no vigentes expiran a 30 días salvo referencias
conservadas por HU-37.
