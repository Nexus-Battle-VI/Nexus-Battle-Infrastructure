"""Elevacion UNICA y controlada de una identidad a un rol administrativo.

POR QUE EXISTE, Y POR QUE DEBERIA DEJAR DE EXISTIR
--------------------------------------------------

Conceder un rol no tiene endpoint. `grantRole` no lo invoca ningun caso de uso y
HU-39 es quien debe exponerlo. Pero HU-39 no puede probarse sin una identidad
administrativa, y no hay ninguna: el pool esta vacio de administradores. El
circulo se rompe una sola vez, a mano, de forma auditable.

**Cuando HU-39 exista, este guion sobra y hay que retirarlo.**

LAS DOS REGLAS QUE NO SE NEGOCIAN
----------------------------------

1. **Se escriben LOS DOS lados.** `account_roles` en PostgreSQL es la fuente de
   verdad; los grupos de Cognito son el reflejo que viaja en el testimonio.
   Agregar solo el grupo daria un token con el rol y una base que no lo
   respalda: seguridad aparente, que es peor que su ausencia.

2. **PostgreSQL PRIMERO, Cognito despues.** Es el orden inverso al de
   `RegisterAccount`, y a proposito. Si esto se rompe a la mitad, importa cual
   de las dos inconsistencias queda:

   - base SI / pool NO  -> el testimonio no lleva el rol -> 403 en todas partes.
     Molesto y visible, pero **no concede nada**.
   - pool SI / base NO  -> el testimonio SI lleva el rol y los cuatro servicios
     lo honran -> **privilegio sin respaldo de la fuente de verdad**.

   Se elige que el fallo caiga del lado que no concede.

3. **Falla cerrado sin segundo factor.** Una cuenta administrativa sin TOTP
   inscrito entra con sola contrasena por la pantalla alojada. Elevar antes de
   inscribir es crear justo el agujero que el resto del trabajo cierra.

Uso:

    python scripts/elevar_rol_bootstrap.py --subject <sub> --role ADMINISTRATOR

Es idempotente: repetirlo no duplica nada y no falla.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from collections.abc import Callable

try:
    import boto3
    from botocore.exceptions import BotoCoreError, ClientError, ProfileNotFound
except ImportError:  # pragma: no cover - depende del entorno de operacion
    print("Falta boto3. Instalar con: pip install boto3", file=sys.stderr)
    raise SystemExit(2)


POOL_POR_DEFECTO = "us-east-1_HrEiSzzKW"
PERFIL_POR_DEFECTO = "nexus-battles"
REGION_POR_DEFECTO = "us-east-1"
NODO_DATOS_POR_DEFECTO = "i-0342c58d99d8c780b"
FACTOR_TOTP = "SOFTWARE_TOKEN_MFA"

ROLES_ADMINISTRATIVOS = ("ADMINISTRATOR", "SUPER_ADMINISTRATOR")


class ErrorElevacion(RuntimeError):
    """Detiene el flujo sin dejar una falsa sensacion de exito."""


def factores_confirmados(detalle: dict[str, object]) -> set[str]:
    """Solo cuentan los factores CONFIRMADOS.

    Se lee `UserMFASettingList` y no `MFAOptions`: el segundo esta obsoleto y no
    refleja TOTP. Un token asociado pero nunca verificado no protege nada, y por
    eso no aparece aqui.
    """
    factores = detalle.get("UserMFASettingList", [])
    if not isinstance(factores, list):
        return set()
    return {factor for factor in factores if isinstance(factor, str)}


def exigir_segundo_factor(cognito, *, pool_id: str, subject: str) -> None:
    detalle = cognito.admin_get_user(UserPoolId=pool_id, Username=subject)

    if FACTOR_TOTP not in factores_confirmados(detalle):
        raise ErrorElevacion(
            f"La identidad {subject} no tiene un segundo factor confirmado. "
            "Elevarla ahora crearia una cuenta administrativa que entra con sola "
            "contrasena por la pantalla alojada. Inscribe TOTP primero con "
            "scripts/inscribir_totp_administrativo.py."
        )


def ejecutar_sql_en_el_nodo(
    ssm,
    *,
    instancia: str,
    sentencias: list[str],
    esperar: Callable[[float], None] = time.sleep,
) -> str:
    """Ejecuta psql en el nodo de datos, que no es alcanzable desde fuera.

    La contrasena se lee del `.env` del nodo y **no viaja en el comando**: SSM
    guarda el texto de la invocacion, y mandarla ahi seria dejarla escrita en el
    historial de la cuenta.
    """
    comandos = [
        "cd /opt/nexus",
        "PASS=$(grep -m1 ^DB_PASSWORD= .env | cut -d= -f2-)",
        'P="docker exec -e PGPASSWORD=$PASS nexus-battles-vi-data-postgres-1 '
        'psql -U account -d account -At"',
        *sentencias,
    ]

    envio = ssm.send_command(
        InstanceIds=[instancia],
        DocumentName="AWS-RunShellScript",
        Parameters={"commands": comandos},
    )
    identificador = envio["Command"]["CommandId"]

    for _ in range(30):
        esperar(3)
        invocacion = ssm.get_command_invocation(
            CommandId=identificador, InstanceId=instancia
        )
        if invocacion["Status"] not in ("Pending", "InProgress", "Delayed"):
            break
    else:  # pragma: no cover - solo si el nodo no responde nunca
        raise ErrorElevacion("El nodo de datos no respondio al comando.")

    if invocacion["Status"] != "Success":
        raise ErrorElevacion(
            f"El comando en el nodo de datos fallo: {invocacion.get('StandardErrorContent', '')}"
        )

    return str(invocacion.get("StandardOutputContent", ""))


def elevar(
    cognito,
    ssm,
    *,
    pool_id: str,
    instancia: str,
    subject: str,
    rol: str,
    mostrar: Callable[[str], None] = print,
    esperar: Callable[[float], None] = time.sleep,
) -> None:
    if rol not in ROLES_ADMINISTRATIVOS:
        raise ErrorElevacion(
            f"El rol {rol} no es administrativo. Este guion existe solo para la "
            "primera elevacion administrativa."
        )

    mostrar(f"1/4  Comprobando el segundo factor de {subject}")
    exigir_segundo_factor(cognito, pool_id=pool_id, subject=subject)
    mostrar("     Correcto: tiene TOTP confirmado.")

    # PostgreSQL primero. Ver la regla 2 de la cabecera de este fichero.
    mostrar("2/4  Escribiendo el rol en account_roles (fuente de verdad)")
    salida = ejecutar_sql_en_el_nodo(
        ssm,
        instancia=instancia,
        sentencias=[
            f"$P -c \"insert into account_roles (account_id, role) "
            f"select id, '{rol}' from accounts where subject = '{subject}' "
            f"on conflict do nothing;\"",
            f"$P -c \"select r.role from account_roles r join accounts a on a.id = r.account_id "
            f"where a.subject = '{subject}' order by 1;\"",
        ],
        esperar=esperar,
    )

    roles_en_base = {linea.strip() for linea in salida.splitlines() if linea.strip()}
    roles_en_base = {r for r in roles_en_base if not r.startswith("INSERT")}

    if rol not in roles_en_base:
        raise ErrorElevacion(
            f"El rol no quedo en account_roles. Puede que no exista ninguna cuenta "
            f"con subject = {subject}: la identidad existe antes que la cuenta, y "
            "quiza falte completar el registro. NO se toco Cognito."
        )
    mostrar(f"     Correcto: {sorted(roles_en_base)}")

    mostrar("3/4  Reflejando el rol en el grupo de Cognito")
    cognito.admin_add_user_to_group(UserPoolId=pool_id, Username=subject, GroupName=rol)

    mostrar("4/4  Comprobando los dos lados")
    grupos = {
        g["GroupName"]
        for g in cognito.admin_list_groups_for_user(UserPoolId=pool_id, Username=subject)["Groups"]
    }

    if rol not in grupos:
        raise ErrorElevacion(
            f"El rol quedo en la base pero NO en el pool. El testimonio no lo "
            f"llevara y la cuenta recibira 403. Grupos actuales: {sorted(grupos)}"
        )

    mostrar("")
    mostrar(f"Elevacion completa. base={sorted(roles_en_base)}  pool={sorted(grupos)}")
    mostrar("Los dos lados coinciden. Cierra sesion y vuelve a entrar: el rol")
    mostrar("viaja en el testimonio, y el que tengas ahora todavia no lo lleva.")


def argumentos(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Elevacion unica y controlada a un rol administrativo (bootstrap de HU-39)."
    )
    parser.add_argument("--subject", required=True, help="`sub` de Cognito de la identidad.")
    parser.add_argument("--role", default="ADMINISTRATOR", choices=list(ROLES_ADMINISTRATIVOS))
    parser.add_argument("--pool-id", default=os.environ.get("POOL_ID", POOL_POR_DEFECTO))
    parser.add_argument(
        "--instancia-datos", default=os.environ.get("NODO_DATOS", NODO_DATOS_POR_DEFECTO)
    )
    parser.add_argument("--profile", default=os.environ.get("AWS_PROFILE", PERFIL_POR_DEFECTO))
    parser.add_argument("--region", default=os.environ.get("AWS_REGION", REGION_POR_DEFECTO))
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = argumentos(argv)
    try:
        sesion = boto3.Session(profile_name=args.profile, region_name=args.region)
        elevar(
            sesion.client("cognito-idp"),
            sesion.client("ssm"),
            pool_id=args.pool_id,
            instancia=args.instancia_datos,
            subject=args.subject,
            rol=args.role,
        )
        return 0
    except (ErrorElevacion, ClientError, BotoCoreError, ProfileNotFound) as error:
        print(f"No se elevo el rol: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
