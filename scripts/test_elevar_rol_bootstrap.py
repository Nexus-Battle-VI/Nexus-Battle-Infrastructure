"""Pruebas del bootstrap de elevacion, sin tocar AWS ni la base."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


RUTA = Path(__file__).with_name("elevar_rol_bootstrap.py")
ESPECIFICACION = importlib.util.spec_from_file_location("elevar_rol_bootstrap", RUTA)
if ESPECIFICACION is None or ESPECIFICACION.loader is None:  # pragma: no cover
    raise RuntimeError("No se pudo cargar el bootstrap.")
MODULO = importlib.util.module_from_spec(ESPECIFICACION)
ESPECIFICACION.loader.exec_module(MODULO)


class CognitoFalso:
    def __init__(self, *, con_factor: bool = True) -> None:
        self.con_factor = con_factor
        self.grupos: list[str] = []
        self.altas = 0

    def admin_get_user(self, **_: object) -> dict[str, object]:
        return {"UserMFASettingList": [MODULO.FACTOR_TOTP] if self.con_factor else []}

    def admin_add_user_to_group(self, **parametros: object) -> dict[str, object]:
        self.altas += 1
        self.grupos.append(str(parametros["GroupName"]))
        return {}

    def admin_list_groups_for_user(self, **_: object) -> dict[str, object]:
        return {"Groups": [{"GroupName": g} for g in self.grupos]}


class SsmFalso:
    """Devuelve lo que devolveria psql: una fila por linea."""

    def __init__(self, roles_tras_insertar: list[str]) -> None:
        self.roles = roles_tras_insertar
        self.invocaciones = 0

    def send_command(self, **_: object) -> dict[str, object]:
        self.invocaciones += 1
        return {"Command": {"CommandId": "cmd-1"}}

    def get_command_invocation(self, **_: object) -> dict[str, object]:
        return {"Status": "Success", "StandardOutputContent": "\n".join(self.roles)}


class ElevarTest(unittest.TestCase):
    def test_escribe_los_dos_lados_y_los_comprueba(self) -> None:
        cognito = CognitoFalso()
        ssm = SsmFalso(["PLAYER", "ADMINISTRATOR"])

        MODULO.elevar(
            cognito,
            ssm,
            pool_id="pool",
            instancia="i-datos",
            subject="sujeto-1",
            rol="ADMINISTRATOR",
            mostrar=lambda _: None,
            esperar=lambda _: None,
        )

        self.assertEqual(cognito.grupos, ["ADMINISTRATOR"])
        self.assertEqual(ssm.invocaciones, 1)

    def test_falla_cerrado_sin_segundo_factor_y_no_toca_nada(self) -> None:
        """Elevar sin TOTP crearia justo el agujero que el resto del trabajo cierra.

        Se comprueba ademas que NO se escribio en ninguno de los dos lados: un
        fallo que ya hubiera insertado en la base dejaria basura que nadie sabe
        que esta ahi.
        """
        cognito = CognitoFalso(con_factor=False)
        ssm = SsmFalso(["PLAYER"])

        with self.assertRaises(MODULO.ErrorElevacion):
            MODULO.elevar(
                cognito,
                ssm,
                pool_id="pool",
                instancia="i-datos",
                subject="sujeto-1",
                rol="ADMINISTRATOR",
                mostrar=lambda _: None,
                esperar=lambda _: None,
            )

        self.assertEqual(ssm.invocaciones, 0)
        self.assertEqual(cognito.grupos, [])

    def test_no_toca_cognito_si_la_base_no_quedo_con_el_rol(self) -> None:
        """La regla del orden, comprobada.

        Si la escritura en la fuente de verdad no cuajo -por ejemplo, porque la
        identidad existe pero la CUENTA todavia no-, agregar el grupo daria un
        testimonio con un rol que la base no respalda. Eso es privilegio sin
        respaldo, y es lo que este guion no debe producir nunca.
        """
        cognito = CognitoFalso()
        ssm = SsmFalso(["PLAYER"])  # el insert no afecto ninguna fila

        with self.assertRaises(MODULO.ErrorElevacion):
            MODULO.elevar(
                cognito,
                ssm,
                pool_id="pool",
                instancia="i-datos",
                subject="sujeto-sin-cuenta",
                rol="ADMINISTRATOR",
                mostrar=lambda _: None,
                esperar=lambda _: None,
            )

        self.assertEqual(cognito.altas, 0, "No debe tocar el pool si la base no cuajo.")

    def test_rechaza_un_rol_que_no_es_administrativo(self) -> None:
        with self.assertRaises(MODULO.ErrorElevacion):
            MODULO.elevar(
                CognitoFalso(),
                SsmFalso(["PLAYER"]),
                pool_id="pool",
                instancia="i-datos",
                subject="sujeto-1",
                rol="PLAYER",
                mostrar=lambda _: None,
                esperar=lambda _: None,
            )

    def test_es_idempotente(self) -> None:
        """Repetirlo no debe fallar ni duplicar: `on conflict do nothing` en la
        base, y Cognito ignora un alta repetida en el mismo grupo."""
        cognito = CognitoFalso()
        ssm = SsmFalso(["PLAYER", "ADMINISTRATOR"])
        parametros = dict(
            pool_id="pool",
            instancia="i-datos",
            subject="sujeto-1",
            rol="ADMINISTRATOR",
            mostrar=lambda _: None,
            esperar=lambda _: None,
        )

        MODULO.elevar(cognito, ssm, **parametros)
        MODULO.elevar(cognito, ssm, **parametros)

        self.assertEqual(sorted(set(cognito.grupos)), ["ADMINISTRATOR"])


if __name__ == "__main__":
    unittest.main()
