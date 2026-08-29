"""Pruebas unitarias del asistente de inscripcion TOTP, sin llamadas a AWS."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path
from typing import cast


RUTA = Path(__file__).with_name("inscribir_totp_administrativo.py")
ESPECIFICACION = importlib.util.spec_from_file_location("inscribir_totp_administrativo", RUTA)
if ESPECIFICACION is None or ESPECIFICACION.loader is None:  # pragma: no cover
    raise RuntimeError("No se pudo cargar el asistente TOTP.")
MODULO = importlib.util.module_from_spec(ESPECIFICACION)
ESPECIFICACION.loader.exec_module(MODULO)


class CognitoFalso:
    def __init__(self, *, inscrito: bool = False, reto: str | None = None) -> None:
        self.inscrito = inscrito
        self.reto = reto
        self.preferencia: dict[str, object] | None = None
        self.autenticaciones = 0

    def admin_get_user(self, **parametros: object) -> dict[str, object]:
        factores = [MODULO.FACTOR_TOTP] if self.inscrito else []
        return {"Username": parametros["Username"], "UserMFASettingList": factores}

    def admin_initiate_auth(self, **parametros: object) -> dict[str, object]:
        self.autenticaciones += 1
        if self.reto is not None:
            return {"ChallengeName": self.reto, "Session": "sesion-no-expuesta"}
        return {"AuthenticationResult": {"AccessToken": "token-no-expuesto"}}

    def associate_software_token(self, **parametros: object) -> dict[str, object]:
        return {"SecretCode": "CLAVE-SOLO-PARA-LA-PRUEBA"}

    def verify_software_token(self, **parametros: object) -> dict[str, object]:
        self.inscrito = parametros.get("UserCode") == "123456"
        return {"Status": "SUCCESS" if self.inscrito else "ERROR"}

    def set_user_mfa_preference(self, **parametros: object) -> dict[str, object]:
        self.preferencia = cast(dict[str, object], parametros["SoftwareTokenMfaSettings"])
        return {}


class InscribirTotpTest(unittest.TestCase):
    def test_asocia_verifica_prefiere_y_confirma_el_factor(self) -> None:
        cognito = CognitoFalso()
        secretos = iter(["Contrasena-segura", "123456"])
        salida: list[str] = []

        inscrito = MODULO.inscribir_totp(
            cognito,
            pool_id="pool",
            client_id="cliente",
            username="admin@example.test",
            leer_secreto=lambda _: next(secretos),
            mostrar=salida.append,
        )

        self.assertTrue(inscrito)
        self.assertEqual(cognito.autenticaciones, 1)
        self.assertEqual(cognito.preferencia, {"Enabled": True, "PreferredMfa": True})
        self.assertIn("    CLAVE-SOLO-PARA-LA-PRUEBA", salida)
        detalle = cognito.admin_get_user(UserPoolId="pool", Username="admin@example.test")
        self.assertIn(MODULO.FACTOR_TOTP, MODULO.factores_confirmados(detalle))

    def test_el_aviso_va_despues_de_la_clave_y_no_antes(self) -> None:
        """El aviso estaba ARRIBA, y la primera persona que uso el guion pego el
        bloque entero -clave incluida- en un chat.

        No fue un descuido suyo: un aviso situado antes queda fuera de la
        seleccion cuando alguien copia "lo que acaba de salir". Se afirma el
        ORDEN, no la presencia: el texto ya estaba y no evito nada.
        """
        cognito = CognitoFalso()
        secretos = iter(["Contrasena-segura", "123456"])
        salida: list[str] = []

        MODULO.inscribir_totp(
            cognito,
            pool_id="pool",
            client_id="cliente",
            username="admin@example.test",
            leer_secreto=lambda _: next(secretos),
            mostrar=salida.append,
            limpiar_pantalla=lambda: None,
        )

        posicion_clave = salida.index("    CLAVE-SOLO-PARA-LA-PRUEBA")
        avisos = [i for i, linea in enumerate(salida) if "NO la pegues" in linea]

        self.assertTrue(avisos, "El aviso debe aparecer.")
        self.assertGreater(min(avisos), posicion_clave)

    def test_limpia_la_pantalla_al_confirmar(self) -> None:
        """La clave sobrevive en el bufer de la ventana aunque el guion termine.

        Pedir "cierra el terminal" es pedir que alguien se acuerde.
        """
        cognito = CognitoFalso()
        secretos = iter(["Contrasena-segura", "123456"])
        limpiezas: list[int] = []

        MODULO.inscribir_totp(
            cognito,
            pool_id="pool",
            client_id="cliente",
            username="admin@example.test",
            leer_secreto=lambda _: next(secretos),
            mostrar=lambda _: None,
            limpiar_pantalla=lambda: limpiezas.append(1),
        )

        self.assertEqual(len(limpiezas), 1)

    def test_no_limpia_cuando_no_se_llego_a_inscribir(self) -> None:
        """Control del caso anterior. Si limpiara siempre, la prueba de arriba
        pasaria sin comprobar que la limpieza va atada al exito, y ademas se
        borraria la pantalla tras un fallo, escondiendo el error."""
        cognito = CognitoFalso(inscrito=True)
        limpiezas: list[int] = []

        MODULO.inscribir_totp(
            cognito,
            pool_id="pool",
            client_id="cliente",
            username="admin@example.test",
            leer_secreto=lambda _: self.fail("No debe pedir credenciales."),
            mostrar=lambda _: None,
            limpiar_pantalla=lambda: limpiezas.append(1),
        )

        self.assertEqual(limpiezas, [])

    def test_no_reemplaza_una_clave_ya_confirmada(self) -> None:
        cognito = CognitoFalso(inscrito=True)

        inscrito = MODULO.inscribir_totp(
            cognito,
            pool_id="pool",
            client_id="cliente",
            username="admin@example.test",
            leer_secreto=lambda _: self.fail("No debe pedir credenciales."),
            mostrar=lambda _: None,
        )

        self.assertFalse(inscrito)
        self.assertEqual(cognito.autenticaciones, 0)

    def test_falla_cerrado_ante_un_reto_no_soportado(self) -> None:
        cognito = CognitoFalso(reto="NEW_PASSWORD_REQUIRED")

        with self.assertRaises(MODULO.ErrorInscripcion):
            MODULO.inscribir_totp(
                cognito,
                pool_id="pool",
                client_id="cliente",
                username="admin@example.test",
                leer_secreto=lambda _: "Contrasena-segura",
                mostrar=lambda _: None,
            )

    def test_rechaza_codigo_que_no_tiene_seis_digitos(self) -> None:
        cognito = CognitoFalso()
        secretos = iter(["Contrasena-segura", "12345"])

        with self.assertRaises(MODULO.ErrorInscripcion):
            MODULO.inscribir_totp(
                cognito,
                pool_id="pool",
                client_id="cliente",
                username="admin@example.test",
                leer_secreto=lambda _: next(secretos),
                mostrar=lambda _: None,
            )


if __name__ == "__main__":
    unittest.main()
