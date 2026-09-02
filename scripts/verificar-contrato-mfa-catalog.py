"""Verifica que contrato y despliegue MFA evolucionen juntos.

No sustituye el lint de OpenAPI ni ``docker compose config``. Fija las piezas
transversales que esas herramientas no relacionan: metodo exigido, codigos 403
y 503, misma variable de secreto y direccion interna de Account.
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
if compose.count(secret_binding) != 2:
    raise SystemExit(
        "FALLO: Account y Catalog deben recibir exactamente la misma variable "
        "INTERNAL_SERVICE_AUTH_SECRET."
    )

for fragment in (
    "INTERNAL_SERVICE_ALLOWED_SERVICES: catalog",
    "ACCOUNT_INTERNAL_URL: http://account:3000",
    "INTERNAL_SERVICE_NAME: catalog",
    "INTERNAL_TIMEOUT_MS: ${INTERNAL_TIMEOUT_MS:-2000}",
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

print("Contrato MFA de Account, Catalog e Infrastructure alineado.")
