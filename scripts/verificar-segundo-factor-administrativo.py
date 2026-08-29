"""Toda cuenta administrativa del pool debe tener un segundo factor confirmado.

POR QUE ESTE GUION EXISTE
-------------------------

El pool esta en `mfa_configuration = OPTIONAL`. Segun AWS, con OPTIONAL
**solo se reta a quien tiene un factor configurado**. Eso es exactamente lo que
ADR-004 quiere -segundo factor para los roles administrativos y no para los
jugadores- pero lo consigue por INSCRIPCION, no por imposicion del pool.

La diferencia importa: una cuenta administrativa SIN factor inscrito entra con
sola contrasena, en silencio, y los cinco servicios honran ese testimonio. No
hay ningun error que lo delate. Este guion es el control que lo delata.

`LoginAccount` de Account ya falla cerrado en ese caso, pero solo cubre
`POST /api/sessions`. Quien entre por la pantalla alojada de Cognito no pasa por
Account, y por eso la comprobacion tiene que hacerse contra el pool.

NO SE EJECUTA EN CI: necesita credenciales de AWS. Se ejecuta a mano al crear una
cuenta administrativa y antes de cada demostracion.

    python scripts/verificar-segundo-factor-administrativo.py

Codigo de salida 1 si alguna cuenta administrativa no tiene factor confirmado.
"""
import os
import sys

try:
    import boto3
except ImportError:  # pragma: no cover
    print("Falta boto3. Instalar con: pip install boto3", file=sys.stderr)
    raise SystemExit(2)

POOL = os.environ.get("POOL_ID", "us-east-1_HrEiSzzKW")
PERFIL = os.environ.get("AWS_PROFILE", "nexus-battles")
REGION = os.environ.get("AWS_REGION", "us-east-1")

# Los grupos cuyos miembros exigen segundo factor. Debe coincidir con
# ADMINISTRATIVE_ROLES de Nexus-Battle-Account/src/domain/entities/Role.ts.
#
# Se admite sobreescribirlos por entorno SOLO para poder comprobar que este
# guion falla cuando debe fallar. Mientras no exista ninguna cuenta
# administrativa, la ejecucion normal pasa por ausencia, y una comprobacion que
# solo sabe pasar no comprueba nada. El control es:
#
#     GRUPOS_ADMINISTRATIVOS=PLAYER python scripts/verificar-segundo-factor-administrativo.py
#
# que debe SALIR CON 1 al encontrar jugadores sin factor. No cambia ningun
# permiso en el pool: solo mira otro grupo.
GRUPOS_ADMINISTRATIVOS = tuple(
    g.strip()
    for g in os.environ.get("GRUPOS_ADMINISTRATIVOS", "ADMINISTRATOR,SUPER_ADMINISTRATOR").split(",")
    if g.strip()
)

sesion = boto3.Session(profile_name=PERFIL, region_name=REGION)
cognito = sesion.client("cognito-idp")


def miembros(grupo):
    """Usuarios del grupo. Pagina: un pool con muchas cuentas no cabe en una."""
    salida = []
    testigo = None
    while True:
        parametros = {"UserPoolId": POOL, "GroupName": grupo, "Limit": 60}
        if testigo:
            parametros["NextToken"] = testigo
        respuesta = cognito.list_users_in_group(**parametros)
        salida.extend(respuesta.get("Users", []))
        testigo = respuesta.get("NextToken")
        if not testigo:
            return salida


def factores(usuario):
    """Factores CONFIRMADOS de la cuenta.

    Se lee `UserMFASettingList` y no `MFAOptions`: el segundo esta obsoleto y
    solo refleja SMS. Un token de aplicacion asociado pero nunca verificado NO
    aparece aqui, que es justo lo que se quiere: asociar no protege, verificar
    si.
    """
    detalle = cognito.admin_get_user(UserPoolId=POOL, Username=usuario)
    return list(detalle.get("UserMFASettingList", []))


def main():
    configuracion = cognito.get_user_pool_mfa_config(UserPoolId=POOL)
    modo = configuracion.get("MfaConfiguration")

    print(f"Pool {POOL}: mfa_configuration = {modo}")
    if modo == "OFF":
        print("FALLO: con OFF no se reta a nadie, tenga factor o no.")
        return 1
    if modo == "ON":
        print("El pool exige factor a todo el mundo. Esta comprobacion sobra,")
        print("pero se ejecuta igual porque ON tambien afecta a los jugadores.")

    administrativas = {}
    for grupo in GRUPOS_ADMINISTRATIVOS:
        for usuario in miembros(grupo):
            administrativas.setdefault(usuario["Username"], set()).add(grupo)

    if not administrativas:
        print("No hay ninguna cuenta administrativa en el pool.")
        print("Correcto por ausencia: no hay nada expuesto que proteger.")
        return 0

    desprotegidas = []
    for nombre, grupos in sorted(administrativas.items()):
        inscritos = factores(nombre)
        etiqueta = ",".join(sorted(grupos))
        if inscritos:
            print(f"  OK       {nombre}  [{etiqueta}]  factores: {','.join(inscritos)}")
        else:
            print(f"  SIN 2FA  {nombre}  [{etiqueta}]")
            desprotegidas.append(nombre)

    if desprotegidas:
        print()
        print(f"FALLO: {len(desprotegidas)} cuenta(s) administrativa(s) sin segundo factor.")
        print("Entran con sola contrasena por la pantalla alojada, y los cinco")
        print("servicios honran ese testimonio. Inscribir el factor o retirar el rol.")
        return 1

    print()
    print(f"Correcto: las {len(administrativas)} cuentas administrativas tienen factor confirmado.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
