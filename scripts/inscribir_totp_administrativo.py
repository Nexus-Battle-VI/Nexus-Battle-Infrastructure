"""Inscribe TOTP en una identidad confirmada antes de concederle un rol admin.

Este asistente no crea usuarios, no asigna grupos y no modifica PostgreSQL.
Autentica al propio usuario, asocia su aplicacion autenticadora y confirma que
Cognito registre ``SOFTWARE_TOKEN_MFA``. La elevacion de rol debe ocurrir solo
despues de que este guion termine correctamente.

La contrasena y el codigo TOTP se leen sin eco. No se guardan en archivos ni se
incluyen en los mensajes de error. La clave de configuracion se muestra una sola
vez para que el propietario la introduzca directamente en su autenticador; no
debe copiarse a incidencias, chats ni documentos.
"""

from __future__ import annotations

import argparse
import getpass
import os
import re
import sys
from collections.abc import Callable
from typing import Protocol

try:
    import boto3
    from botocore.config import Config
    from botocore.exceptions import BotoCoreError, ClientError, ProfileNotFound
except ImportError:  # pragma: no cover - depende del entorno de operacion
    print("Falta boto3. Instalar con: pip install boto3", file=sys.stderr)
    raise SystemExit(2)


POOL_POR_DEFECTO = "us-east-1_HrEiSzzKW"
CLIENTE_POR_DEFECTO = "vqtjlpsemjr5kjtsb97fnr1qp"
PERFIL_POR_DEFECTO = "nexus-battles"
REGION_POR_DEFECTO = "us-east-1"
FACTOR_TOTP = "SOFTWARE_TOKEN_MFA"
CODIGO_TOTP = re.compile(r"^[0-9]{6}$")


class ErrorInscripcion(RuntimeError):
    """El flujo no puede continuar sin dejar una falsa sensacion de exito."""


class ClienteCognito(Protocol):
    """Superficie minima del cliente Cognito usada por el asistente."""

    def admin_get_user(self, **parametros: object) -> dict[str, object]: ...

    def admin_initiate_auth(self, **parametros: object) -> dict[str, object]: ...

    def associate_software_token(self, **parametros: object) -> dict[str, object]: ...

    def verify_software_token(self, **parametros: object) -> dict[str, object]: ...

    def set_user_mfa_preference(self, **parametros: object) -> dict[str, object]: ...


def factores_confirmados(detalle: dict[str, object]) -> set[str]:
    """Lee la lista vigente; ``MFAOptions`` esta obsoleta y no incluye TOTP."""
    factores = detalle.get("UserMFASettingList", [])
    if not isinstance(factores, list):
        return set()
    return {factor for factor in factores if isinstance(factor, str)}


def exigir_token_de_acceso(respuesta: dict[str, object]) -> str:
    """Extrae el token sin aceptar retos que este asistente no sabe resolver."""
    reto = respuesta.get("ChallengeName")
    if isinstance(reto, str) and reto:
        raise ErrorInscripcion(
            f'Cognito devolvio el reto "{reto}". Completa primero el alta y la '
            "confirmacion de la identidad desde la aplicacion web."
        )

    autenticacion = respuesta.get("AuthenticationResult")
    if not isinstance(autenticacion, dict):
        raise ErrorInscripcion("Cognito no devolvio una sesion autenticada utilizable.")

    token = autenticacion.get("AccessToken")
    if not isinstance(token, str) or not token:
        raise ErrorInscripcion("Cognito no devolvio el token de acceso del usuario.")
    return token


def inscribir_totp(
    cognito: ClienteCognito,
    *,
    pool_id: str,
    client_id: str,
    username: str,
    leer_secreto: Callable[[str], str] = getpass.getpass,
    mostrar: Callable[[str], None] = print,
) -> bool:
    """Inscribe y verifica TOTP. Devuelve ``False`` si ya estaba inscrito."""
    detalle_inicial = cognito.admin_get_user(UserPoolId=pool_id, Username=username)
    if FACTOR_TOTP in factores_confirmados(detalle_inicial):
        mostrar("La identidad ya tiene TOTP confirmado; no se reemplazo su clave.")
        return False

    contrasena = leer_secreto("Contrasena de la identidad (no se mostrara): ")
    if not contrasena:
        raise ErrorInscripcion("La contrasena no puede estar vacia.")

    autenticacion = cognito.admin_initiate_auth(
        UserPoolId=pool_id,
        ClientId=client_id,
        AuthFlow="ADMIN_USER_PASSWORD_AUTH",
        AuthParameters={"USERNAME": username, "PASSWORD": contrasena},
    )
    token = exigir_token_de_acceso(autenticacion)

    asociacion = cognito.associate_software_token(AccessToken=token)
    clave = asociacion.get("SecretCode")
    if not isinstance(clave, str) or not clave:
        raise ErrorInscripcion("Cognito no devolvio una clave TOTP para asociar.")

    mostrar("")
    mostrar("Introduce AHORA esta clave en tu aplicacion autenticadora:")
    mostrar(clave)
    mostrar("No la copies a chats, incidencias ni documentos.")
    mostrar("")

    codigo = leer_secreto("Codigo de seis digitos del autenticador: ").strip()
    if CODIGO_TOTP.fullmatch(codigo) is None:
        raise ErrorInscripcion("El codigo TOTP debe contener exactamente seis digitos.")

    verificacion = cognito.verify_software_token(
        AccessToken=token,
        UserCode=codigo,
        FriendlyDeviceName="Nexus Battles VI",
    )
    if verificacion.get("Status") != "SUCCESS":
        raise ErrorInscripcion("Cognito no confirmo la asociacion del autenticador.")

    cognito.set_user_mfa_preference(
        AccessToken=token,
        SoftwareTokenMfaSettings={"Enabled": True, "PreferredMfa": True},
    )

    detalle_final = cognito.admin_get_user(UserPoolId=pool_id, Username=username)
    if FACTOR_TOTP not in factores_confirmados(detalle_final):
        raise ErrorInscripcion(
            "La verificacion respondio correctamente, pero el factor no aparece confirmado."
        )

    mostrar("TOTP confirmado. La identidad ya puede elevarse de rol de forma segura.")
    return True


def construir_cliente(*, perfil: str, region: str) -> ClienteCognito:
    """Crea una sola sesion y un solo cliente con reintentos acotados."""
    sesion = boto3.Session(profile_name=perfil, region_name=region)
    configuracion = Config(
        retries={"total_max_attempts": 3, "mode": "standard"},
        connect_timeout=5,
        read_timeout=10,
    )
    return sesion.client("cognito-idp", config=configuracion)


def argumentos(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Inscribe TOTP antes de conceder un rol administrativo."
    )
    parser.add_argument("--username", required=True, help="Correo o username de Cognito.")
    parser.add_argument("--pool-id", default=os.environ.get("POOL_ID", POOL_POR_DEFECTO))
    parser.add_argument(
        "--client-id", default=os.environ.get("COGNITO_CLIENT_ID", CLIENTE_POR_DEFECTO)
    )
    parser.add_argument("--profile", default=os.environ.get("AWS_PROFILE", PERFIL_POR_DEFECTO))
    parser.add_argument("--region", default=os.environ.get("AWS_REGION", REGION_POR_DEFECTO))
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = argumentos(argv)
    try:
        cliente = construir_cliente(perfil=args.profile, region=args.region)
        inscribir_totp(
            cliente,
            pool_id=args.pool_id,
            client_id=args.client_id,
            username=args.username,
        )
        return 0
    except (ErrorInscripcion, ClientError, BotoCoreError, ProfileNotFound) as error:
        print(f"No se pudo inscribir TOTP: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\nInscripcion cancelada; no se concedio ningun rol.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
