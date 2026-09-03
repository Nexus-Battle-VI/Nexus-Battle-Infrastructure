"""Verifica que contrato y despliegue del contrato interno evolucionen juntos.

No sustituye el lint de OpenAPI ni ``docker compose config``. Fija las piezas
transversales que esas herramientas no relacionan: metodo exigido, codigos 403
y 503, misma variable de secreto y direcciones internas.

EL SECRETO ES UNO SOLO Y LO COMPARTEN TRES SERVICIOS desde HU-34: Account lo
verifica, Catalog lo usa en las dos direcciones -cliente de la evidencia de
segundo factor y servidor del descuento de inventario- y Commerce lo usa para
pedir ese descuento. Si dos de ellos recibieran variables distintas, la firma no
cuadraria y el sintoma seria un 401 sin ninguna explicacion visible.
"""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def require(text: str, fragment: str, source: str) -> None:
    if fragment not in text:
        raise SystemExit(f"FALLO: {source} no contiene {fragment!r}")


openapi = read("docs/contracts/catalog-product-v1.openapi.yaml")
for fragment in (
    "method=AUTHENTICATOR_APP",
    "'403':\n          $ref: '#/components/responses/Forbidden'",
    "'503':\n          $ref: '#/components/responses/ServiceUnavailable'",
    "ServiceUnavailable:",
    "code: MFA_EVIDENCE_UNAVAILABLE",
):
    require(openapi, fragment, "OpenAPI de Catalog")

compose = read("compose/nodes/app.yml")
secret_binding = "INTERNAL_SERVICE_AUTH_SECRET: ${INTERNAL_SERVICE_AUTH_SECRET:-}"
SERVICIOS_DEL_CONTRATO = 3
if compose.count(secret_binding) != SERVICIOS_DEL_CONTRATO:
    raise SystemExit(
        "FALLO: Account, Catalog y Commerce deben recibir exactamente la misma "
        "variable INTERNAL_SERVICE_AUTH_SECRET. Si se suma otro servicio al "
        "contrato interno, ajusta SERVICIOS_DEL_CONTRATO junto al compose."
    )

for fragment in (
    "INTERNAL_SERVICE_ALLOWED_SERVICES: catalog",
    "ACCOUNT_INTERNAL_URL: http://account:3000",
    "INTERNAL_SERVICE_NAME: catalog",
    "INTERNAL_TIMEOUT_MS: ${INTERNAL_TIMEOUT_MS:-2000}",
    # HU-34: el descuento de inventario va en sentido contrario, de Commerce a
    # Catalog. Sin estas dos, la compra se completa SIN descontar y el tiraje
    # limitado deja de aplicarse sin que nada lo delate.
    "CATALOG_INTERNAL_URL: http://catalog:3003",
    "INTERNAL_SERVICE_NAME: commerce",
):
    require(compose, fragment, "compose del nodo de aplicaciones")

terraform_main = read("infra/envs/prod/main.tf")
terraform_variables = read("infra/envs/prod/variables.tf")
require(
    terraform_main,
    "INTERNAL_SERVICE_AUTH_SECRET = var.internal_service_auth_secret",
    "Terraform de produccion",
)
require(
    terraform_variables,
    'variable "internal_service_auth_secret"',
    "variables de Terraform",
)
secret_variable = re.search(
    r'variable "internal_service_auth_secret"\s*\{(?P<body>.*?)\n\}',
    terraform_variables,
    re.DOTALL,
)
if secret_variable is None:
    raise SystemExit("FALLO: no se pudo interpretar internal_service_auth_secret.")
require(secret_variable.group("body"), "sensitive   = true", "variable del secreto interno")

print("Contrato interno de Account, Catalog, Commerce e Infrastructure alineado.")
