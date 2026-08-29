"""Descripciones de reglas de grupo de seguridad, contra el juego de AWS."""
import glob
import io
import re
import sys

PERMITIDOS = set(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    ". _-:/()#,@[]+=&;{}!$*"
)
BLOQUE = re.compile(r'resource\s+"(aws_(?:vpc_)?security_group[a-z_]*)"[^{]*\{')

fallos = []
for fichero in sorted(glob.glob("infra/**/*.tf", recursive=True)):
    texto = io.open(fichero, encoding="utf-8").read()
    for bloque in BLOQUE.finditer(texto):
        # Se recorta desde el inicio del recurso hasta el siguiente `resource`,
        # que es suficiente para no confundir con descripciones de variables.
        siguiente = texto.find("\nresource ", bloque.end())
        cuerpo = texto[bloque.end(): siguiente if siguiente != -1 else len(texto)]
        for m in re.finditer(r'description\s*=\s*"([^"]*)"', cuerpo):
            fuera = sorted({c for c in m.group(1) if c not in PERMITIDOS})
            if fuera:
                linea = texto[: bloque.end() + m.start()].count("\n") + 1
                fallos.append((fichero, linea, fuera, m.group(1)[:60]))

for fichero, linea, fuera, texto_desc in fallos:
    print(f"{fichero}:{linea}: caracteres no admitidos {fuera} en: {texto_desc}")

if fallos:
    print()
    print("AWS solo admite en estas descripciones: a-zA-Z0-9. _-:/()#,@[]+=&;{}!$*")
    sys.exit(1)

print("Descripciones de reglas de seguridad dentro del juego admitido por AWS.")
