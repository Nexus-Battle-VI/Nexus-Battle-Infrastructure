"""Verifica que contrato y despliegue del contrato interno evolucionen juntos.

No sustituye el lint de OpenAPI ni ``docker compose config``. Fija las piezas
transversales que esas herramientas no relacionan: metodo exigido, codigos 403
y 503, misma variable de secreto y direcciones internas.

El secreto es compartido por Account, Catalog, Commerce, Player-Inventory y
Notifications. Ademas de la evidencia MFA protege las reservas de stock, la
entrega del lote y la confirmacion por correo del ecommerce.
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
services = dict(re.findall(r"^  ([a-z-]+):\n(.*?)(?=^  [a-z-]+:|\Z)", compose, re.M | re.S))
for name in ("account", "catalog", "commerce", "inventory", "notifications"):
    service = services.get(name, "")
    bindings = re.findall(
        r"^\s+INTERNAL_SERVICE_AUTH_SECRET:\s*(.+)$", service, re.M
    )
    if len(bindings) != 1 or re.fullmatch(
        r"\$\{INTERNAL_SERVICE_AUTH_SECRET:(?:-|\?[^}]*)\}", bindings[0]
    ) is None:
        raise SystemExit(
            f"FALLO: {name} debe recibir exactamente una vez la variable "
            "compartida INTERNAL_SERVICE_AUTH_SECRET."
        )

for name, fragment in (
    ("commerce", "COMMERCE_INTEGRATION_MODE: http"),
    ("commerce", "INVENTORY_INTERNAL_URL: http://inventory:3002"),
    ("commerce", "NOTIFICATIONS_INTERNAL_URL: http://notifications:3003"),
    ("notifications", "PURCHASE_HTTP_ENABLED: 'true'"),
    ("notifications", "PURCHASE_HTTP_PORT: 3003"),
    ("notifications", "PURCHASE_INBOX_DRIVER: mongo"),
    ("notifications", "MONGO_DB_NAME: notifications"),
    ("catalog", "ASSETS_STORAGE_DRIVER: ${ASSETS_STORAGE_DRIVER:-memory}"),
    ("catalog", "PRODUCT_ASSETS_BUCKET_NAME: ${PRODUCT_ASSETS_BUCKET_NAME:-}"),
    ("catalog", "AWS_REGION: ${AWS_REGION:-us-east-1}"),
):
    require(services[name], fragment, f"compose del servicio {name}")

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
require(
    terraform_variables,
    "!var.arrancar_stack || length(trimspace(var.internal_service_auth_secret)) >= 32",
    "validacion del secreto antes del arranque",
)
for key, value in (
    ("ASSETS_STORAGE_DRIVER", '"s3"'),
    ("PRODUCT_ASSETS_BUCKET_NAME", "module.product_assets.bucket_id"),
    ("AWS_REGION", "var.region"),
):
    if re.search(rf"^\s+{key}\s*=\s*{re.escape(value)}\s*$", terraform_main, re.M) is None:
        raise SystemExit(f"FALLO: Terraform no transmite {key} al nodo de aplicaciones.")

bootstrap = read("infra/modules/compute/templates/bootstrap.sh.tftpl")
require(bootstrap, 'estado.setName === "rs0" && estado.isWritablePrimary', "espera de Mongo")
require(bootstrap, "const limite = Date.now() + 180000", "limite de espera de Mongo")
if bootstrap.index('estado.setName === "rs0"') > bootstrap.index("docker compose up -d"):
    raise SystemExit("FALLO: las migraciones deben esperar al primario de Mongo.")

print("Contratos internos de cinco servicios, assets S3 y arranque de Mongo alineados.")
